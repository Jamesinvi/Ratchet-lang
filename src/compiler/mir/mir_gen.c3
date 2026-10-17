module compiler::mir;

import compiler;
import log;
import debug;
import common;
import globals;
import std::collections::list;

faultdef MIR_GEN_ERROR;

enum MirGenResult
{
	OK,
	ERROR,
}

struct MirGenerator
{
	ProgramAst* inputAst; // input
	SymbolTable* symbolTable; // input
	MirProgram output; // output
	List{MirOperand} bindings; // temp, Indexed by SymbolIdx
	List{MirFunctionIdx} functionBindings; // temp, Indexed by SymbolIdx
	Stack{MirLoopContext} loopContexts; // temp, Indexed by loop depth
	DynamicArenaAllocator localAllocator;
	Allocator outputAllocator;
	MirRegisterID currentReg;
	MirBlockIdx currentBlock;
	SymbolIdx currentReceiverSymbolIdx;
}

fn MirProgram? generate_mir(ProgramAst* ast, SymbolTable* symbolTable, Allocator ouputAllocator)
{
	MirGenerator mirGenerator = { };
	mirGenerator.init(ast, symbolTable, ouputAllocator);
	defer mirGenerator.deinit();
	MirGenResult mirGenResult = mirGenerator.run();
	if (mirGenResult != MirGenResult.OK)
	{
		return MIR_GEN_ERROR~;
	}
	return mirGenerator.output;
}


fn void MirGenerator.init(MirGenerator* this, ProgramAst* inputAst, SymbolTable* symbolTable, Allocator outputAllocator)
{
	this.inputAst = inputAst;
	this.symbolTable = symbolTable;
	this.outputAllocator = outputAllocator;

	this.localAllocator = { };
	this.localAllocator.init(mem, 1024);

	this.output = { };
	this.currentReg = 0;
	this.currentBlock = 0;
	this.currentReceiverSymbolIdx = compiler::analyzer::NO_SYMBOL;

	this.output.init(this.outputAllocator, 512);
	this.bindings.init(&this.localAllocator, this.symbolTable.symbols.len());
	this.functionBindings.init(&this.localAllocator, this.symbolTable.symbols.len());

	common::list_append_fill{MirOperand}(&this.bindings, placeHolderOperand, this.symbolTable.symbols.len());
	common::list_append_fill{MirFunctionIdx}(&this.functionBindings, NO_FUNCTION, this.symbolTable.symbols.len());
}

fn void MirGenerator.deinit(MirGenerator* this)
{
	this.localAllocator.free();
	this.loopContexts.free();
}

fn MirGenResult MirGenerator.run(MirGenerator* this)
{
	// Give every callable symbol a stable MIR index before lowering any bodies.
	foreach (&analysis : this.symbolTable.functions)
	{
		MirFunction function = {
			.symbolIdx = analysis.symbolIdx,
			.params = analysis.params,
			.returnType = analysis.returnType,
			.receiverSymbolIdx = analysis.receiverSymbolIdx,
			.kind = analysis.kind,
		};
		switch (analysis.kind)
		{
			case CallTargetKind.FREE_FUN:
				function.sourceFnDecl = analysis.fnDeclIdx;
				function.sourceMethodIdx = NO_METHOD;
			case CallTargetKind.METHOD:
				function.sourceStructDecl = analysis.methodId.structDeclIdx;
				function.sourceMethodIdx = analysis.methodId.methodIdx;
			case CallTargetKind.NATIVE_FUN:
				function.nativeFnIdx = analysis.nativeFnIdx;
			case CallTargetKind.NATIVE_METHOD:
				function.nativeFnIdx = analysis.nativeFnIdx;
			default: unreachable();
		}
		assert(this.output.functions.len() < int::max);
		this.functionBindings[analysis.symbolIdx] = (MirFunctionIdx)this.output.functions.len();
		this.output.functions.push(function);
	}

	// Global declarations carry static initial values; they do not emit executable MIR.
	foreach (stmtIdx : this.inputAst.globalBlock.globalStatements)
	{
		Stmt* stmt = &this.inputAst.statements[stmtIdx];
		assert(stmt.kind == StmtKind.DECL);
		SymbolIdx symbolIdx = this.symbolTable.stmtSymbols[stmtIdx];
		MirGlobal global = {
			.symbolIdx = symbolIdx,
			.type = this.symbolTable.symbols[symbolIdx].type,
			.hasInitializer = stmt.varDecl.init != parser::NO_IDX,
		};
		if (global.hasInitializer)
		{
			global.initialValue = this.lower_global_initializer(stmt.varDecl.init);
		}
		this.output.globals.push(global);
	}

	// Function pass: all callees now exist, so forward calls and recursion are safe.
	for (int functionIdx = 0; functionIdx < (int)this.output.functions.len(); functionIdx++)
	{
		this.lower_function_body(functionIdx);
	}


	return MirGenResult.OK;
}

fn MirOperand MirGenerator.lower_global_initializer(MirGenerator* this, ExprIdx exprIdx)
{
	Expr* expr = &this.inputAst.expressions[exprIdx];
	switch (expr.kind)
	{
		case ExprKind.INT: return { .kind = MirOperandKind.IMM_INT, .immInt = expr.intLiteral };
		case ExprKind.FLOAT: return { .kind = MirOperandKind.IMM_FLOAT, .immFloat = expr.floatLiteral };
		case ExprKind.DOUBLE: return { .kind = MirOperandKind.IMM_DOUBLE, .immDouble = expr.doubleLiteral };
		case ExprKind.BOOL: return { .kind = MirOperandKind.IMM_BOOL, .immBool = expr.boolLiteral };
		case ExprKind.NULL: return { .kind = MirOperandKind.IMM_NULL, .immInt = 0 };
		case ExprKind.STRING_LITERAL: return { .kind = MirOperandKind.IMM_STRING, .immString = this.inputAst.names[expr.stringLiteral] };
		default: unreachable("Analysis should guarantee constant global initializers");
	}
}

fn void MirGenerator.lower_function_body(MirGenerator* this, MirFunctionIdx functionIdx)
{
	MirFunction* function = &this.output.functions[functionIdx];
	if (function.kind == CallTargetKind.NATIVE_FUN || function.kind == CallTargetKind.NATIVE_METHOD) return;
	Decl* sourceDecl = &this.inputAst.declarations[function.sourceFnDecl];
	StmtIdx bodyIdx;
	if (function.kind == CallTargetKind.FREE_FUN)
	{
		debug::@log_mir("lowering func: '%s'", this.inputAst.names[sourceDecl.nameIdx].text());
		bodyIdx = sourceDecl.fnDecl.body;
	}
	else
	{
		MethodDeclAst* method = &sourceDecl.structDecl.methods[function.sourceMethodIdx];
		debug::@log_mir("lowering method: '%s'", this.inputAst.names[method.nameIdx].text());
		bodyIdx = method.body;
	}

	// clear out all temporaries and operands
	common::list_set_values{MirOperand}(&this.bindings, placeHolderOperand);
	this.currentReg = 0;
	this.currentReceiverSymbolIdx = function.receiverSymbolIdx;

	Stmt funcBody       = this.inputAst.statements[bodyIdx];
	BlockStmt bodyBlock = funcBody.blockStmt;

	function.blocksStart = this.blocks_len();

	// Parameters behave like pre-existing locals at function entry.
	foreach (paramSymbolIdx : function.params)
	{
		MirPlace paramPlace = {
			.baseSymbolIdx = paramSymbolIdx,
			.type = this.symbolTable.symbols[paramSymbolIdx].type,
			.isIndirect = this.symbolTable.symbols[paramSymbolIdx].passMode != ParamPassMode.VALUE,
		};
		MirPlaceIdx placeIdx = this.push_place_get_idx(&paramPlace);
		this.bindings[paramSymbolIdx] = {
			.kind = MirOperandKind.PLACE,
			.placeIdx = placeIdx,
		};
	}

	MirBlockIdx blockIdx = this.blocks_len();
	MirBlock block = {
		.idx = blockIdx,
		.instructionsStart = this.instructions_len(),
		.instructionsEnd = this.instructions_len(),
		.terminator = NO_TERMINATOR,
	};
	this.output.blocks.push(block);
	this.currentBlock = blockIdx;

	foreach (stmtIdx : bodyBlock.stmts)
	{
		// exit block if already terminated by break/continue/return etc
		if (this.is_current_block_terminated())
		{
			break;
		}
		this.lower_stmt(stmtIdx);
	}

	MirBlock* loweredBlock = &this.output.blocks[this.currentBlock];
	loweredBlock.instructionsEnd = this.instructions_len();
	if (loweredBlock.terminator == NO_TERMINATOR)
	{
		MirTerminator defaultTerm = {
			.opCode = MirTerminatorOp.RETURN,
			.operandsStart = this.operands_len(),
			.operandsEnd = this.operands_len(),
		};
		loweredBlock.terminator = this.push_terminator_get_idx(&defaultTerm);
	}
	function.blocksEnd = this.blocks_len();
}

fn void MirGenerator.lower_stmt(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	debug::@log_mir("lowering stmt: '%s'", stmt.kind);

	switch (stmt.kind)
	{
		case StmtKind.ECHO: this.lower_echo(stmtIdx);
		case StmtKind.DECL: this.lower_var_decl(stmtIdx);
		case StmtKind.IF: this.lower_if(stmtIdx);
		case StmtKind.WHILE: this.lower_while(stmtIdx);
		case StmtKind.RETURN: this.lower_return(stmtIdx);
		case StmtKind.BREAK: this.lower_break(stmtIdx);
		case StmtKind.CONTINUE: this.lower_continue(stmtIdx);
		case StmtKind.EXPR: this.lower_expr(stmt.exprStmt);
		default:

			{
				log::errlogn("Unsupported statement %s in mir gen", stmt.kind);
				unreachable();
			}
			;
	}
}

fn void MirGenerator.lower_echo(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt             = &this.inputAst.statements[stmtIdx];
	// Echo has its own special expr so lower it directly
	MirOperand echoOperand = this.lower_expr(stmt.echoStmt);
	// as usual get "start" before pushing, then "end" after
	OperandIdx start       = this.operands_len();
	this.output.operands.push(echoOperand);
	OperandIdx end = this.operands_len();

	MirInstruction instruction = {
		.opCode = MirOpCode.ECHO,
		.type = this.symbolTable.exprTypes[stmt.echoStmt],
		.result = NO_REG,
		.operandsStart = start,
		.operandsEnd = end,
		.sourceStmtIdx = stmtIdx,
	};
	this.output.instructions.push(instruction);
}

fn void MirGenerator.lower_while(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt      = &this.inputAst.statements[stmtIdx];
	BlockStmt* body = &this.inputAst.statements[stmt.whileStmt.body].blockStmt;

	// 1. Split before condition.
	MirBlockIdx condBlockIdx = this.push_empty_block_get_idx();
	this.terminate_current_block_with_jump(condBlockIdx);

	// 2. Lower condition in its own block.
	this.currentBlock = condBlockIdx;
	MirOperand condOperand = this.lower_expr(stmt.whileStmt.cond);

	// 3. Create body block now. Join is still unknown.
	MirBlockIdx bodyBlockIdx = this.push_empty_block_get_idx();

	OperandIdx branchStart = this.operands_len();
	this.output.operands.push(condOperand);
	this.output.operands.push({ .kind = MirOperandKind.BLOCK, .blockIdx = bodyBlockIdx });
	this.output.operands.push({ .kind = MirOperandKind.BLOCK, .blockIdx = NO_BLOCK }); // join, patched later
	OperandIdx branchEnd = this.operands_len();

	MirTerminator branchTerm = {
		.opCode = MirTerminatorOp.BRANCH,
		.operandsStart = branchStart,
		.operandsEnd = branchEnd,
	};

	this.output.blocks[condBlockIdx].instructionsEnd = this.instructions_len();
	this.output.blocks[condBlockIdx].terminator = this.push_terminator_get_idx(&branchTerm);

	// 4. Lower body.
	this.currentBlock = bodyBlockIdx;
	this.loopContexts.push({ });
	this.loopContexts.peek_ref().breakTargets.init(&this.localAllocator);
	this.loopContexts.peek_ref().continueTarget = condBlockIdx;
	foreach (bodyStmtIdx : body.stmts)
	{
		// exit block if already terminated by break/continue/return etc
		if (this.is_current_block_terminated())
		{
			break;
		}
		this.lower_stmt(bodyStmtIdx);
	}

	// 5. Close body by jumping back to condition.
	this.terminate_current_block_with_jump(condBlockIdx);

	// 6. Now create join, after body is finalized, and patch false target.
	MirBlockIdx joinBlockIdx = this.push_empty_block_get_idx();
	this.output.operands[(sz)branchStart + 2].blockIdx = joinBlockIdx;

	// 7. Patch every "break" jump produced while lowering this loop body.
	MirLoopContext loopContext = this.loopContexts.pop();
	foreach (breakTerminatorIdx : loopContext.breakTargets)
	{
		MirTerminator* breakTerminator = &this.output.terminators[breakTerminatorIdx];
		assert(breakTerminator.opCode == MirTerminatorOp.JUMP);

		OperandIdx targetOperandIdx = breakTerminator.operandsStart;
		this.output.operands[targetOperandIdx].blockIdx = joinBlockIdx;
	}


	// 8. Continue after loop.
	this.currentBlock = joinBlockIdx;
}


fn void MirGenerator.lower_if(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt          = &this.inputAst.statements[stmtIdx];
	BlockStmt* thenStmt = &this.inputAst.statements[stmt.ifStmt.thenBlock].blockStmt;
	bool hasElse        = stmt.ifStmt.elseBlock != parser::NO_IDX;
	BlockStmt* elseStmt = null;
	if (hasElse)
	{
		elseStmt = &this.inputAst.statements[stmt.ifStmt.elseBlock].blockStmt;
	}
	MirBlockIdx branchBlockIdx = this.currentBlock;
	MirOperand condOperand     = this.lower_expr(stmt.ifStmt.cond);

	// Create branch terminator now with placeholder block operands.
	OperandIdx branchStart = this.operands_len();
	this.output.operands.push(condOperand);
	this.output.operands.push({ .kind = MirOperandKind.BLOCK, .blockIdx = NO_BLOCK }); // then
	this.output.operands.push({ .kind = MirOperandKind.BLOCK, .blockIdx = NO_BLOCK }); // false
	OperandIdx branchEnd = this.operands_len();

	MirTerminator branchTerm = {
		.opCode = MirTerminatorOp.BRANCH,
		.operandsStart = branchStart,
		.operandsEnd = branchEnd,
	};

	this.output.blocks[branchBlockIdx].instructionsEnd = this.instructions_len();
	this.output.blocks[branchBlockIdx].terminator = this.push_terminator_get_idx(&branchTerm);

	// Lower then.
	MirBlockIdx thenBlockIdx = this.push_empty_block_get_idx();
	this.currentBlock = thenBlockIdx;

	foreach (thenStmtIdx : thenStmt.stmts)
	{
		// exit block if already terminated by break/continue/return etc
		if (this.is_current_block_terminated())
		{
			break;
		}
		this.lower_stmt(thenStmtIdx);
	}

	MirBlockIdx thenExitBlockIdx = this.currentBlock;
	this.seal_current_block();

	// Lower else, if present.
	MirBlockIdx elseBlockIdx     = NO_BLOCK;
	MirBlockIdx elseExitBlockIdx = NO_BLOCK;
	if (hasElse)
	{
		elseBlockIdx = this.push_empty_block_get_idx();
		this.currentBlock = elseBlockIdx;

		foreach (elseStmtIdx : elseStmt.stmts)
		{
			// exit block if already terminated by break/continue/return etc
			if (this.is_current_block_terminated())
			{
				break;
			}
			this.lower_stmt(elseStmtIdx);
		}

		elseExitBlockIdx = this.currentBlock;
		this.seal_current_block();
	}

	// Create join after both bodies are lowered.
	// This matters because then/else bodies may allocate nested blocks.
	MirBlockIdx joinBlockIdx = this.push_empty_block_get_idx();

	// Patch branch targets now that real block ids are known.
	MirBlockIdx falseTarget = hasElse ? elseBlockIdx : joinBlockIdx;

	this.output.operands[(sz)branchStart + 1].blockIdx = thenBlockIdx;
	this.output.operands[(sz)branchStart + 2].blockIdx = falseTarget;

	// Close then exit into join.
	this.currentBlock = thenExitBlockIdx;
	this.add_jump_to_current_block(joinBlockIdx);

	// Close else exit into join, if there is an else.
	if (hasElse)
	{
		this.currentBlock = elseExitBlockIdx;
		this.add_jump_to_current_block(joinBlockIdx);
	}

	// Continue lowering following statements into join.
	this.currentBlock = joinBlockIdx;
}


fn void MirGenerator.lower_var_decl(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	debug::@log_mir("lowering var decl: '%s'", this.inputAst.names[stmt.varDecl.nameIdx].text());

	SymbolIdx stmtSymbolIdx = this.symbolTable.stmtSymbols[stmtIdx];
	Symbol* symbol          = &this.symbolTable.symbols[stmtSymbolIdx];
	MirPlace newPlace = {
		.baseSymbolIdx = stmtSymbolIdx,
		.type = symbol.type,
		.isGlobal = symbol.kind == SymbolKind.GLOBAL_VAR,
	};
	MirPlaceIdx placeIdx = this.push_place_get_idx(&newPlace);
	MirOperand operand   = { .kind = MirOperandKind.PLACE, .placeIdx = placeIdx };

	this.bindings[stmtSymbolIdx] = operand;
	if (stmt.varDecl.init != parser::NO_IDX)
	{
		this.lower_var_init(stmtIdx, stmtSymbolIdx);
	}
	else
	{
		OperandIdx start = this.operands_len();
		this.output.operands.push(operand);
		OperandIdx end     = this.operands_len();
		TypeInfo storeType = symbol.type;
		MirInstruction storeInst = {
			.opCode = MirOpCode.ZERO_BYTES,
			.type = storeType,
			.result = NO_REG,
			.operandsStart = start,
			.operandsEnd = end,
			.sourceStmtIdx = stmtIdx,
		};
		this.output.instructions.push(storeInst);
	}
}


fn void MirGenerator.lower_var_init(MirGenerator* this, StmtIdx stmtIdx, SymbolIdx stmtSymbolIdx)
{
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	debug::@log_mir("lowering var init: '%s'", this.inputAst.names[stmt.varDecl.nameIdx].text());

	TypeInfo storeType = this.symbolTable.exprTypes[stmt.varDecl.init];
	if (stmtSymbolIdx < this.symbolTable.symbols.len())
	{
		storeType = this.symbolTable.symbols[stmtSymbolIdx].type;
	}
	MirOperand initValue    = this.lower_expr(stmt.varDecl.init);
	MirOperand placeOperand = this.bindings[stmtSymbolIdx];
	OperandIdx start        = this.operands_len();
	this.output.operands.push(placeOperand);
	this.output.operands.push(initValue);
	OperandIdx end = this.operands_len();


	MirInstruction storeInst = {
		.opCode = MirOpCode.STORE,
		.type = storeType,
		.result = NO_REG,
		.operandsStart = start,
		.operandsEnd = end,
		.sourceStmtIdx = stmtIdx,
	};
	this.output.instructions.push(storeInst);
}

fn void MirGenerator.lower_return(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	debug::@log_mir("lowering return");
	MirOperand returnValue = placeHolderOperand;

	if (stmt.retStmt.value != parser::NO_IDX)
	{
		returnValue = this.lower_expr(stmt.retStmt.value);
	}
	// Only the final return value belongs to the terminator's operand slice.
	OperandIdx start = this.operands_len();
	if (stmt.retStmt.value != parser::NO_IDX)
	{
		this.output.operands.push(returnValue);
	}
	OperandIdx end = this.operands_len();

	MirTerminator term = {
		.opCode = MirTerminatorOp.RETURN,
		.operandsStart = start,
		.operandsEnd = end,
	};

	MirTerminatorIdx termIdx = this.push_terminator_get_idx(&term);
	this.output.blocks[this.currentBlock].terminator = termIdx;
}

fn void MirGenerator.lower_break(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	debug::@log_mir("lowering break");
	MirTerminatorIdx breakTerminatorIdx = this.terminate_current_block_with_jump(NO_BLOCK);
	this.loopContexts.peek_ref().breakTargets.push(breakTerminatorIdx);
}

fn void MirGenerator.lower_continue(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	debug::@log_mir("lowering continue");
	MirTerminatorIdx continueTerminatorIdx = this.terminate_current_block_with_jump(this.loopContexts.peek().continueTarget);
}

fn MirOperand MirGenerator.lower_expr(MirGenerator* this, ExprIdx exprIdx)
{
	Expr* expr = &this.inputAst.expressions[exprIdx];
	debug::@log_mir("lowering expr: '%s'", expr.kind);

	switch (expr.kind)
	{
		case ExprKind.INT: return { .kind = MirOperandKind.IMM_INT, .immInt = expr.intLiteral };
		case ExprKind.FLOAT: return { .kind = MirOperandKind.IMM_FLOAT, .immFloat = expr.floatLiteral };
		case ExprKind.DOUBLE: return { .kind = MirOperandKind.IMM_DOUBLE, .immDouble = expr.doubleLiteral };
		case ExprKind.BOOL: return { .kind = MirOperandKind.IMM_BOOL, .immBool = expr.boolLiteral };
		case ExprKind.NULL: return { .kind = MirOperandKind.IMM_NULL, .immInt = 0 };
		case ExprKind.STRING_LITERAL: return { .kind = MirOperandKind.IMM_STRING, .immString = this.inputAst.names[expr.stringLiteral] };
		case ExprKind.BINARY:
			MirOpCode opCode = ast_to_mir_op(expr.binary.op);
			MirOperand rhs = this.lower_expr(expr.binary.rhs);
			MirOperand lhs;
			MirRegisterID resultReg;
			if (opCode == MirOpCode.STORE)
			{
				lhs = this.lower_place(expr.binary.lhs);
				resultReg = NO_REG;
			}
			else
			{
				lhs = this.lower_expr(expr.binary.lhs);
				resultReg = this.currentReg++;
			}
			OperandIdx start = this.operands_len();
			this.output.operands.push(lhs);
			this.output.operands.push(rhs);

			OperandIdx end = this.operands_len();
			MirInstruction inst = {
				.opCode = opCode,
				.type = this.symbolTable.exprTypes[exprIdx],
				.result = resultReg,
				.operandsStart = start,
				.operandsEnd = end,
				.sourceExprIdx = exprIdx,
			};
			this.output.instructions.push(inst);
			return { .kind = MirOperandKind.REGISTER, .regId = resultReg };
		case ExprKind.CALL: return this.lower_call(exprIdx);
		case ExprKind.THIS: nextcase;
		case ExprKind.VAR: return this.load_place_value(this.lower_place(exprIdx), exprIdx);
		case ExprKind.NEW:
			// We have type which stores the whole ref type
			// We only need 1 operand: the value to which initialize the ref
			// Store in a register
			SymbolIdx varExprSymbolIdx = this.symbolTable.exprSymbols[exprIdx];
			TypeInfo varExprType = this.symbolTable.exprTypes[exprIdx];
			MirRegisterID resultReg = this.currentReg++;
			OperandIdx start, end;
			MirOpCode opCode;
			// Arrays have a separate opcode, and need to lower a different expression (arraySize instead of init)
			if (varExprType.type == ValueType.ARR_REF_GC || varExprType.type == ValueType.ARR_REF_NOGC)
			{
				MirOperand arrSize = this.lower_expr(expr.new.arraySize);
				start = this.operands_len();
				this.output.operands.push(arrSize);
				end = this.operands_len();
				opCode = MirOpCode.ALLOC_ARRAY;
			}
			else
			{
				MirOperand val = this.lower_expr(expr.new.init);
				start = this.operands_len();
				this.output.operands.push(val);
				end = this.operands_len();
				opCode = MirOpCode.ALLOC_GC;
			}

			MirInstruction inst = {
				.opCode = opCode,
				.type = varExprType,
				.result = resultReg,
				.operandsStart = start,
				.operandsEnd = end,
				.sourceExprIdx = exprIdx,
			};
			this.output.instructions.push(inst);

			return { .kind = MirOperandKind.REGISTER, .regId = resultReg };
		case ExprKind.MEMBER:
			TypeInfo baseType = this.symbolTable.exprTypes[expr.member.base];
			if (baseType.is_inline_array())
			{
				// Evaluate the base, including calls and checked indexing, even though
				// the array's length/capacity is a compile-time constant.
				this.lower_value_place(expr.member.base);
				return { .kind = MirOperandKind.IMM_INT, .immInt = baseType.arraySize };
			}
			nextcase;
		case ExprKind.INDEXER: return this.load_place_value(this.lower_place(exprIdx), exprIdx);
		case ExprKind.CAST:
			MirOperand source = this.lower_expr(expr.cast.value);
			MirRegisterID result = this.currentReg++;

			OperandIdx start = this.operands_len();
			this.output.operands.push(source);
			OperandIdx end = this.operands_len();

			MirInstruction inst = {
				.opCode = MirOpCode.AS,
				.type = this.symbolTable.exprTypes[exprIdx], // destination type
				.result = result,
				.operandsStart = start,
				.operandsEnd = end,
				.sourceExprIdx = exprIdx,
			};

			this.output.instructions.push(inst);
			return {
				.kind = MirOperandKind.REGISTER,
				.regId = result,
			};
		default:

			{
				unreachable();
			}
	}
}

fn MirOperand MirGenerator.lower_call(MirGenerator* this, ExprIdx callExprIdx)
{
	Expr* callExpr          = &this.inputAst.expressions[callExprIdx];
	TypeInfo returnType     = this.symbolTable.exprTypes[callExprIdx];
	MirRegisterID resultReg = returnType.type == ValueType.NULL ? NO_REG : this.currentReg++;

	CallTarget target          = this.symbolTable.callTargets[callExprIdx]!!;
	MirFunctionIdx functionIdx = this.functionBindings[target.functionSymbolIdx];
	assert(functionIdx != NO_FUNCTION);
	MirFunction* calleeFunction = &this.output.functions[functionIdx];
	MirOperand callee           = { .kind = MirOperandKind.FUNCTION, .fnCalleeIdx = functionIdx };

	List{MirOperand} callOperands = { };
	sz operandCount               = (sz)callExpr.call.argsEnd - callExpr.call.argsStart + 2;
	callOperands.init(&this.localAllocator, operandCount);
	callOperands.push(callee);

	if (calleeFunction.kind == CallTargetKind.METHOD)
	{
		ExprIdx receiverExprIdx = target.receiverExprIdx;
		MirOperand receiver;
		if (receiverExprIdx != parser::NO_IDX)
		{
			receiver = this.lower_place(receiverExprIdx);
		}
		else
		{
			assert(this.currentReceiverSymbolIdx != compiler::analyzer::NO_SYMBOL);
			receiver = this.bindings[this.currentReceiverSymbolIdx];
			assert(receiver.kind == MirOperandKind.PLACE);
		}
		callOperands.push(receiver);
	}
	else if (calleeFunction.kind == CallTargetKind.NATIVE_METHOD)
	{
		ExprIdx receiverExprIdx = target.receiverExprIdx;
		MirOperand receiver     = this.lower_place(receiverExprIdx);
		callOperands.push(receiver);
	}

	int explicitParamOffset = (calleeFunction.kind == CallTargetKind.METHOD || calleeFunction.kind == CallTargetKind.NATIVE_METHOD) ? 1 : 0;
	int explicitArgIdx      = 0;
	for (ExprIdx i = callExpr.call.argsStart; i < callExpr.call.argsEnd; i++)
	{
		SymbolIdx paramSymbolIdx = calleeFunction.params[(sz)(explicitParamOffset + explicitArgIdx)];
		ParamPassMode passMode   = this.symbolTable.symbols[paramSymbolIdx].passMode;
		ExprIdx argExprIdx       = this.inputAst.args[i].exprIdx;
		// in/inout params are "places"
		MirOperand arg           = passMode == ParamPassMode.VALUE ? this.lower_expr(argExprIdx) : this.lower_place(argExprIdx);
		callOperands.push(arg);
		explicitArgIdx++;
	}

	// Child expressions may have emitted their own operands already; append only the
	// semantic call operands here so the CALL instruction owns a clean slice.
	OperandIdx start = this.operands_len();
	this.output.operands.add_all(&callOperands);
	OperandIdx end = this.operands_len();
	MirInstruction inst = {
		.opCode = MirOpCode.CALL,
		.type = returnType,
		.result = resultReg,
		.operandsStart = start,
		.operandsEnd = end,
		.sourceExprIdx = callExprIdx,
	};
	this.output.instructions.push(inst);
	return { .kind = MirOperandKind.REGISTER, .regId = resultReg };
}

<*
 A place is resolved by MIR: base storage plus a constant byte offset.
 Dynamic access (like heap array indexing) steps emit instructions before the place is consumed.
*>
fn MirOperand MirGenerator.lower_place(MirGenerator* this, ExprIdx exprIdx)
{
	Expr* expr = &this.inputAst.expressions[exprIdx];
	switch (expr.kind)
	{
		case ExprKind.THIS: nextcase;
		case ExprKind.VAR:
			return this.get_or_bind_place(this.symbolTable.exprSymbols[exprIdx]);

		case ExprKind.MEMBER:
			TypeInfo baseType = this.symbolTable.exprTypes[expr.member.base];
			TypeInfo memberType = this.symbolTable.exprTypes[exprIdx];
			// .value handling for int&
			if (baseType.is_builtin_ref_like())
			{
				return this.lower_reference_place(expr.member.base, memberType);
			}
			// array handling for .length and .capacity. Only for ref-like arrays
			if (baseType.is_array())
			{
				assert(!baseType.is_inline_array(), "Inline array metadata has no storage");
				MirOperand operand = this.lower_reference_place(expr.member.base, memberType);
				MirPlace* place    = &this.output.places[operand.placeIdx];
				String name        = this.inputAst.names[expr.member.memberIdx].text();
				// length is stored at offset 0, capacity at offset 4
				place.byteOffset = name == "length" ? 0 : (short)int::size;
				return operand;
			}

			MirOperand base;
			if (baseType.is_struct_ref_like())
			{
				base = this.lower_reference_place(expr.member.base, baseType.pointee_type());
				baseType = baseType.pointee_type();
			}
			else
			{
				base = this.lower_value_place(expr.member.base);
			}
			assert(baseType.type == ValueType.STRUCT);
			MemberIdx fieldIdx = this.symbolTable.memberFieldIndices[exprIdx]!!;
			FieldInfo* field = &globals::structTypes[baseType.structTypeIndex].fieldInfos[fieldIdx];
			MirPlace place = this.output.places[base.placeIdx];
			place.byteOffset += (short)field.offset;
			place.type = memberType;
			return this.create_operand_from_place(place);

		case ExprKind.INDEXER:
			TypeInfo arrayType = this.symbolTable.exprTypes[expr.indexer.base];
			MirOperand base;
			if (arrayType.is_inline_array())
			{
				// Inline arrays can either be stored in stack frame, be a global or a field of some struct. Grab the location
				base = this.address_of_place(this.lower_value_place(expr.indexer.base), expr.indexer.base);
			}
			else
			{
				// Heap arrays store the handle, so get the heap handle before evaluating the index expression.
				base = this.lower_expr(expr.indexer.base);
			}
			MirOperand index = this.lower_expr(expr.indexer.index);
			MirRegisterID result = this.currentReg++;
			OperandIdx start = this.operands_len();
			this.output.operands.push(base);
			this.output.operands.push(index);
			MirInstruction indexIntoArrayInstruction = {
				.opCode = MirOpCode.INDEX_ADDR,
				.type = analyzer::make_type(ValueType.PTR),
				.arrayType = arrayType,
				.result = result,
				.operandsStart = start,
				.operandsEnd = this.operands_len(),
				.sourceExprIdx = exprIdx,
			};
			this.output.instructions.push(indexIntoArrayInstruction);
			MirPlace resultPlace = {
				.baseKind = MirPlaceBaseKind.REGISTER,
				.baseReg = result,
				.type = arrayType.element_type(),
				.isIndirect = true,
			};
			return this.create_operand_from_place(resultPlace);

		default: unreachable("Unsupported lvalue expression in lower_place %s", expr.kind);
	}
}

<*
 Materialize a value-producing base only when it has no existing storage.
*>
fn MirOperand MirGenerator.lower_value_place(MirGenerator* this, ExprIdx exprIdx)
{
	ExprKind kind = this.inputAst.expressions[exprIdx].kind;
	if (kind == ExprKind.VAR || kind == ExprKind.THIS || kind == ExprKind.MEMBER || kind == ExprKind.INDEXER)
	{
		return this.lower_place(exprIdx);
	}
	MirOperand value = this.lower_expr(exprIdx);
	assert(value.kind == MirOperandKind.REGISTER);
	MirPlace resultPlace = {
		.baseKind = MirPlaceBaseKind.REGISTER,
		.baseReg = value.regId,
		.type = this.symbolTable.exprTypes[exprIdx],
	};
	return this.create_operand_from_place(resultPlace);
}

fn MirOperand MirGenerator.lower_reference_place(MirGenerator* this, ExprIdx exprIdx, TypeInfo pointeeType)
{
	MirOperand reference = this.lower_expr(exprIdx);
	OperandIdx start     = this.operands_len();
	this.output.operands.push(reference);
	MirInstruction nullCheckInstruction = {
		.opCode = MirOpCode.CHECK_NONNULL,
		.type = this.symbolTable.exprTypes[exprIdx],
		.result = NO_REG,
		.operandsStart = start,
		.operandsEnd = this.operands_len(),
		.sourceExprIdx = exprIdx,
	};
	this.output.instructions.push(nullCheckInstruction);
	assert(reference.kind == MirOperandKind.REGISTER);
	MirPlace resultPlace = {
		.baseKind = MirPlaceBaseKind.REGISTER,
		.baseReg = reference.regId,
		.type = pointeeType,
		.isIndirect = true,
	};
	return this.create_operand_from_place(resultPlace);
}

fn MirOperand MirGenerator.load_place_value(MirGenerator* this, MirOperand place, ExprIdx exprIdx)
{
	TypeInfo type        = this.output.places[place.placeIdx].type;
	MirRegisterID result = this.currentReg++;
	OperandIdx start     = this.operands_len();
	this.output.operands.push(place);
	this.output.instructions.push(
		{
			.opCode = MirOpCode.LOAD,
			.type = type,
			.result = result,
			.operandsStart = start,
			.operandsEnd = this.operands_len(),
			.sourceExprIdx = exprIdx,
		}
	);
	return { .kind = MirOperandKind.REGISTER, .regId = result };
}

fn MirOperand MirGenerator.address_of_place(MirGenerator* this, MirOperand place, ExprIdx exprIdx)
{
	MirRegisterID result = this.currentReg++;
	OperandIdx start     = this.operands_len();
	this.output.operands.push(place);
	this.output.instructions.push(
		{
			.opCode = MirOpCode.ADDR,
			.type = analyzer::make_type(ValueType.PTR),
			.result = result,
			.operandsStart = start,
			.operandsEnd = this.operands_len(),
			.sourceExprIdx = exprIdx,
		}
	);
	return { .kind = MirOperandKind.REGISTER, .regId = result };
}

fn MirOperand MirGenerator.create_operand_from_place(MirGenerator* this, MirPlace place)
{
	return { .kind = MirOperandKind.PLACE, .placeIdx = this.push_place_get_idx(&place) };
}


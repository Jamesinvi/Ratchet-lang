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
	ProgramAst* inputAst;		// input
	SymbolTable* symbolTable;	// input
	MirProgram output;			// output	
	List{MirOperand} bindings; 	// temp, Indexed by SymbolIdx
	DynamicArenaAllocator localAllocator;
	Allocator outputAllocator;
	MirRegisterID currentReg;
	MirBlockIdx currentBlock;
	SymbolIdx currentReceiverSymbolIdx;
}

fn MirProgram? generate_mir(ProgramAst* ast, SymbolTable* symbolTable, Allocator ouputAllocator)
{
	MirGenerator mirGenerator = {};
	mirGenerator.init(ast, symbolTable, ouputAllocator);
	defer mirGenerator.deinit();
	MirGenResult mirGenResult = mirGenerator.run();
	if(mirGenResult != MirGenResult.OK){
		return MIR_GEN_ERROR~;
	}
	return mirGenerator.output;
}


fn void MirGenerator.init(MirGenerator* this, ProgramAst* inputAst, SymbolTable* symbolTable, Allocator outputAllocator)
{
	this.inputAst = inputAst;
	this.symbolTable = symbolTable;
	this.outputAllocator = outputAllocator;

	this.localAllocator = {};
	this.localAllocator.init(mem, 1024);

	this.output = {};
	this.currentReg = 0;
	this.currentBlock = 0;
	this.currentReceiverSymbolIdx = compiler::analyzer::NO_SYMBOL;

	this.output.init(this.outputAllocator, 1024);
	this.bindings.init(&this.localAllocator, this.symbolTable.symbols.len());

	common::list_append_fill{MirOperand}(&this.bindings, placeHolderOperand, this.symbolTable.symbols.len());
}

fn void MirGenerator.deinit(MirGenerator* this)
{
	this.localAllocator.free();
}

fn MirGenResult MirGenerator.run(MirGenerator* this)
{
	// First pass: give every free function and method a stable MIR function index.
	foreach(idx, &decl : this.inputAst.declarations){
	    assert(idx < int::max);
	    int intIdx = (int)idx;
		if(decl.kind == DeclKind.FUNCTION){
			SymbolIdx symbolIdx = this.symbolTable.declSymbols[intIdx];
			MirFunction function = {
				.sourceDeclIdx = intIdx,
				.sourceMethodIdx = NO_METHOD,
				.paramRange = this.symbolTable.declParamRanges[intIdx],
				.returnType = this.symbolTable.symbols[symbolIdx].type,
				.receiverSymbolIdx = compiler::analyzer::NO_SYMBOL,
			};
			this.output.functions.push(function);
		} else if (decl.kind == DeclKind.STRUCT) {
			this.lower_methods_to_functions(intIdx, &decl.structDecl);
		}
	}

	// Second pass: all callees now exist, so forward calls and recursion are safe.
	for (int functionIdx = 0; functionIdx < (int)this.output.functions.len(); functionIdx++) {
		this.lower_function_body(functionIdx);
	}

	return MirGenResult.OK;
}

fn void MirGenerator.lower_methods_to_functions(MirGenerator* this, DeclIdx structDeclIdx, StructDeclAst* structDecl)
{
	foreach (methodIdx, &method : structDecl.methods) {
		assert(methodIdx < int::max);
		MethodId methodId = {
			.structDeclIdx = structDeclIdx,
			.methodIdx = (int)methodIdx,
		};
		MethodAnalysisInfo* analysis = this.symbolTable.find_method(methodId);
		assert(analysis != null);
		MirFunction function = {
			.sourceDeclIdx = structDeclIdx,
			.sourceMethodIdx = (int)methodIdx,
			.paramRange = analysis.paramRange,
			.returnType = analysis.returnType,
			.receiverSymbolIdx = analysis.receiverSymbolIdx,
		};
		this.output.functions.push(function);
	}
}

fn void MirGenerator.lower_function_body(MirGenerator* this, MirFunctionIdx functionIdx)
{
	MirFunction* function = &this.output.functions[functionIdx];
	Decl* sourceDecl = &this.inputAst.declarations[function.sourceDeclIdx];
	StmtIdx bodyIdx;
	if (function.sourceMethodIdx == NO_METHOD) {
		debug::@log_mir("lowering func: '%s'", this.inputAst.names[sourceDecl.fnDecl.nameIdx].text());
		bodyIdx = sourceDecl.fnDecl.body;
	} else {
		MethodDeclAst* method = &sourceDecl.structDecl.methods[function.sourceMethodIdx];
		debug::@log_mir("lowering method: '%s'", this.inputAst.names[method.nameIdx].text());
		bodyIdx = method.body;
	}

	// clear out all temporaries and operands 
	common::list_set_values{MirOperand}(&this.bindings, placeHolderOperand);
	this.currentReg = 0;
	this.currentReceiverSymbolIdx = function.receiverSymbolIdx;

	Stmt funcBody = this.inputAst.statements[bodyIdx];
	BlockStmt bodyBlock = funcBody.blockStmt;

	function.blocksStart = this.blocks_len();

	// Parameters behave like pre-existing locals at function entry.
	DeclParamRange paramRange = function.paramRange;
	for (int i = paramRange.start; i < paramRange.end; i++) {
		SymbolIdx paramSymbolIdx = this.symbolTable.declParamSymbols[i];
		MirPlace paramPlace = {
			.baseSymbolIdx = paramSymbolIdx,
			.projectionIdx = NO_PROJECTION,
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

	foreach(stmtIdx : bodyBlock.stmts){
		this.lower_stmt(stmtIdx);
	}

	MirBlock* loweredBlock = &this.output.blocks[this.currentBlock];
	loweredBlock.instructionsEnd = this.instructions_len();
	if (loweredBlock.terminator == NO_TERMINATOR) {
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

	switch(stmt.kind)
	{
		case StmtKind.ECHO:		this.lower_echo(stmtIdx);
		case StmtKind.DECL:		this.lower_var_decl(stmtIdx);
		case StmtKind.IF:		this.lower_if(stmtIdx);
		case StmtKind.WHILE:    this.lower_while(stmtIdx);
		case StmtKind.RETURN:	this.lower_return(stmtIdx);
		case StmtKind.EXPR:		this.lower_expr(stmt.exprStmt);
		default: 
		{
			log::errlogn("Unsupported statement %s in mir gen", stmt.kind);
			unreachable();
		};
	}
}

fn void MirGenerator.lower_echo(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	// Echo has its own special expr so lower it directly
	MirOperand echoOperand = this.lower_expr(stmt.echoStmt);
	// as usual get "start" before pushing, then "end" after
    OperandIdx start = this.operands_len();
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
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
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
    foreach (bodyStmtIdx : body.stmts) {
        this.lower_stmt(bodyStmtIdx);
    }

    // 5. Close body by jumping back to condition.
    this.terminate_current_block_with_jump(condBlockIdx);

    // 6. Now create join, after body is finalized, and patch false target.
    MirBlockIdx joinBlockIdx = this.push_empty_block_get_idx();
    this.output.operands[(sz)branchStart + 2].blockIdx = joinBlockIdx;

    // 7. Continue after loop.
    this.currentBlock = joinBlockIdx;
}


fn void MirGenerator.lower_if(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	BlockStmt* thenStmt = &this.inputAst.statements[stmt.ifStmt.thenBlock].blockStmt;
	bool hasElse = stmt.ifStmt.elseBlock != parser::NO_IDX;
	BlockStmt* elseStmt = null;
	if (hasElse) {
		elseStmt = &this.inputAst.statements[stmt.ifStmt.elseBlock].blockStmt;
	}
    MirBlockIdx branchBlockIdx = this.currentBlock;
    MirOperand condOperand = this.lower_expr(stmt.ifStmt.cond);
    
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
    
    foreach (thenStmtIdx : thenStmt.stmts) {
        this.lower_stmt(thenStmtIdx);
    }
    
    MirBlockIdx thenExitBlockIdx = this.currentBlock;
    this.seal_current_block();
    
    // Lower else, if present.
    MirBlockIdx elseBlockIdx = NO_BLOCK;
    MirBlockIdx elseExitBlockIdx = NO_BLOCK;
    if (hasElse) {
        elseBlockIdx = this.push_empty_block_get_idx();
        this.currentBlock = elseBlockIdx;
    
        foreach (elseStmtIdx : elseStmt.stmts) {
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
    if (hasElse) {
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
	MirPlace newPlace = {.baseSymbolIdx = stmtSymbolIdx, .projectionIdx = NO_PROJECTION};
	MirPlaceIdx placeIdx = this.push_place_get_idx(&newPlace);
	MirOperand operand = {.kind = MirOperandKind.PLACE, .placeIdx = placeIdx};

	this.bindings[stmtSymbolIdx] = operand;
	if (stmt.varDecl.init != parser::NO_IDX) {
		this.lower_var_init(stmtIdx, stmtSymbolIdx);
	}
}


fn void MirGenerator.lower_var_init(MirGenerator* this, StmtIdx stmtIdx, SymbolIdx stmtSymbolIdx)
{

	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	debug::@log_mir("lowering var init: '%s'", this.inputAst.names[stmt.varDecl.nameIdx].text());

	TypeInfo storeType = this.symbolTable.exprTypes[stmt.varDecl.init];
	if (stmtSymbolIdx < this.symbolTable.symbols.len()) {
		storeType = this.symbolTable.symbols[stmtSymbolIdx].type;
	}
	MirOperand initValue = this.lower_expr(stmt.varDecl.init);
	MirOperand placeOperand = this.bindings[stmtSymbolIdx];
	OperandIdx start = this.operands_len();
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

	if (stmt.retStmt.value != parser::NO_IDX) {
		returnValue = this.lower_expr(stmt.retStmt.value);
	}
	// Only the final return value belongs to the terminator's operand slice.
	OperandIdx start = this.operands_len();
	if (stmt.retStmt.value != parser::NO_IDX) {
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

fn MirOperand MirGenerator.lower_expr(MirGenerator* this, ExprIdx exprIdx)
{
	Expr* expr = &this.inputAst.expressions[exprIdx];
	debug::@log_mir("lowering expr: '%s'", expr.kind);

	switch (expr.kind)
	{
		case ExprKind.INT:				return {.kind = MirOperandKind.IMM_INT, 	.immInt = expr.intLiteral};
		case ExprKind.FLOAT:			return {.kind = MirOperandKind.IMM_FLOAT, 	.immFloat = expr.floatLiteral};
		case ExprKind.DOUBLE:			return {.kind = MirOperandKind.IMM_DOUBLE, 	.immDouble = expr.doubleLiteral};
		case ExprKind.BOOL:				return {.kind = MirOperandKind.IMM_BOOL, 	.immBool = expr.boolLiteral};
		case ExprKind.NULL:				return {.kind = MirOperandKind.IMM_NULL, 	.immInt = 0};
		case ExprKind.STRING_LITERAL:	return {.kind = MirOperandKind.IMM_STRING, 	.immString = this.inputAst.names[expr.stringLiteral]};
		case ExprKind.BINARY:
			MirOpCode opCode = ast_to_mir_op(expr.binary.op);
			MirOperand rhs = this.lower_expr(expr.binary.rhs);
			MirOperand lhs;
			MirRegisterID resultReg;
			if(opCode == MirOpCode.STORE){
				lhs = this.lower_place(expr.binary.lhs);
				resultReg = NO_REG;
			}else{
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
			return {.kind = MirOperandKind.REGISTER, .regId = resultReg};
		case ExprKind.CALL:	return this.lower_call(exprIdx);
		case ExprKind.THIS: nextcase;
        case ExprKind.VAR:
			SymbolIdx varExprSymbolIdx = this.symbolTable.exprSymbols[exprIdx];
			TypeInfo varExprType = this.symbolTable.exprTypes[exprIdx];
			MirOperand place = this.bindings[varExprSymbolIdx];
			MirRegisterID resultReg = this.currentReg++;
			OperandIdx start = this.operands_len();
			this.output.operands.push(place);
			OperandIdx end = this.operands_len();

			MirInstruction inst = {
				.opCode = MirOpCode.LOAD,
				.type = varExprType,
				.result = resultReg,
				.operandsStart = start,
				.operandsEnd = end,
				.sourceExprIdx = exprIdx,
			};
			this.output.instructions.push(inst);
			return {.kind = MirOperandKind.REGISTER, .regId = resultReg};
		case ExprKind.NEW:
			// We have type which stores the whole ref type
			// We only need 1 operand: the value to which initialize the ref
			// Store in a register
			SymbolIdx varExprSymbolIdx = this.symbolTable.exprSymbols[exprIdx];
			TypeInfo varExprType = this.symbolTable.exprTypes[exprIdx];
			MirRegisterID resultReg = this.currentReg++;
			OperandIdx start = this.operands_len();
			MirOperand val = this.lower_expr(expr.new.init);
			this.output.operands.push(val);
			OperandIdx end = this.operands_len();

			MirInstruction inst = {
				.opCode = MirOpCode.ALLOC_GC,
				.type = varExprType,
				.result = resultReg,
				.operandsStart = start,
				.operandsEnd = end,
				.sourceExprIdx = exprIdx,
			};

			this.output.instructions.push(inst);
			return {.kind = MirOperandKind.REGISTER, .regId = resultReg};
		case ExprKind.MEMBER:
			// Basically the same as VAR but we lower the place since we know it's a member
			TypeInfo memberType = this.symbolTable.exprTypes[exprIdx];
			MirOperand place = this.lower_place(exprIdx);
			MirRegisterID resultReg = this.currentReg++;
			OperandIdx start = this.operands_len();
			this.output.operands.push(place);
			OperandIdx end = this.operands_len();

			MirInstruction inst = {
				.opCode = MirOpCode.LOAD,
				.type = memberType,
				.result = resultReg,
				.operandsStart = start,
				.operandsEnd = end,
				.sourceExprIdx = exprIdx,
			};

			this.output.instructions.push(inst);
			return {.kind = MirOperandKind.REGISTER, .regId = resultReg};
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
			return { .kind = MirOperandKind.REGISTER, .regId = result,};
		default:{
			unreachable();
		}
	}

}

fn MirFunctionIdx MirGenerator.find_free_function(MirGenerator* this, DeclIdx declIdx)
{
	foreach (functionIdx, &function : this.output.functions) {
		if (function.sourceMethodIdx == NO_METHOD && function.sourceDeclIdx == declIdx) {
			assert(functionIdx < int::max);
			return (MirFunctionIdx)functionIdx;
		}
	}
	return NO_FUNCTION;
}

fn MirFunctionIdx MirGenerator.find_method_function(MirGenerator* this, MethodId methodId)
{
	foreach (functionIdx, &function : this.output.functions) {
		if (function.sourceMethodIdx == methodId.methodIdx && function.sourceDeclIdx == methodId.structDeclIdx) {
			assert(functionIdx < int::max);
			return (MirFunctionIdx)functionIdx;
		}
	}
	return NO_FUNCTION;
}

fn MirOperand MirGenerator.lower_call(MirGenerator* this, ExprIdx callExprIdx)
{
	Expr* callExpr = &this.inputAst.expressions[callExprIdx];
	TypeInfo returnType = this.symbolTable.exprTypes[callExprIdx];
	MirRegisterID resultReg = returnType.type == ValueType.NULL ? NO_REG : this.currentReg++;

	CallTarget target = this.symbolTable.callTargets[callExprIdx];
	MirFunctionIdx functionIdx = NO_FUNCTION;
	if (target.kind == CallTargetKind.FREE_FUN) {
		functionIdx = this.find_free_function(target.fnDeclIdx);
	} else if (target.kind == CallTargetKind.METHOD) {
		functionIdx = this.find_method_function(target.methodId);
	}
	assert(functionIdx != NO_FUNCTION);
	MirOperand callee = {.kind = MirOperandKind.FUNCTION, .fnCalleeIdx = functionIdx};

	List{MirOperand} callOperands = {};
	sz operandCount = (sz)callExpr.call.argsEnd - callExpr.call.argsStart + 2;
	callOperands.init(&this.localAllocator, operandCount);
	callOperands.push(callee);

	if (target.kind == CallTargetKind.METHOD) {
		ExprIdx receiverExprIdx = this.symbolTable.callReceiverExpr[callExprIdx];
		MirOperand receiver;
		if (receiverExprIdx != parser::NO_IDX) {
			receiver = this.lower_place(receiverExprIdx);
		} else {
			assert(this.currentReceiverSymbolIdx != compiler::analyzer::NO_SYMBOL);
			receiver = this.bindings[this.currentReceiverSymbolIdx];
			assert(receiver.kind == MirOperandKind.PLACE);
		}
		callOperands.push(receiver);
	}

	for(ExprIdx i = callExpr.call.argsStart; i < callExpr.call.argsEnd; i++){
		MirOperand arg = this.lower_expr(this.inputAst.args[i]);
		callOperands.push(arg);
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
	return {.kind = MirOperandKind.REGISTER, .regId = resultReg};
}

fn MirOperand MirGenerator.lower_place(MirGenerator* this, ExprIdx exprIdx)
{
	Expr* expr = &this.inputAst.expressions[exprIdx];
	switch (expr.kind) {
		case ExprKind.THIS: nextcase;
		case ExprKind.VAR:
			SymbolIdx symbolIdx = this.symbolTable.exprSymbols[exprIdx];
			assert(symbolIdx < this.bindings.len());
			MirOperand place = this.bindings[symbolIdx];
			assert(place.kind == MirOperandKind.PLACE);
			return place;
		case ExprKind.MEMBER:
			MirOperand basePlaceOperand = this.lower_place(expr.member.base);
			assert(basePlaceOperand.kind == MirOperandKind.PLACE);
			MirPlace basePlace = this.output.places[basePlaceOperand.placeIdx];

			// Each projection is part of a chain str.foo.bar.x
			//										   ↑   ↑  ↑_ stores index to 'bar'
			//										   |   |_ stores index to 'foo'
			//										   |_ index is NO_PROJECTION
			// Projection chains are stored backwards: newest node points to previous one.
			// This lets places share common prefixes (e.g. `a.x` reused by `a.x.y`).
			MemberIdx fieldIdx = this.symbolTable.memberFieldIndices[exprIdx];
			MirProjection projection = {
				.fieldIdx = fieldIdx,
				.prevProjectionIdx = basePlace.projectionIdx,
			};
			MirProjectionIdx projectionIdx = this.push_projection_get_idx(&projection);

			MirPlace memberPlace = {
				.baseSymbolIdx = basePlace.baseSymbolIdx,
				.projectionIdx = projectionIdx,
			};
			MirPlaceIdx placeIdx = this.push_place_get_idx(&memberPlace);
			return {.kind = MirOperandKind.PLACE, .placeIdx = placeIdx};
		default:
			unreachable("Unsupported lvalue expression in lower_place %s", expr.kind);
	}

}

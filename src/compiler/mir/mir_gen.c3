module compiler::mir;

import compiler;
import log;
import debug;
import common;
import globals;
import std::collections::list;


enum MirGenResult
{
	OK,
	ERROR,
}

struct MirGenerator
{
	ProgramAst* inputAst;
	SymbolTable* symbolTable;
	MirProgram output;
	DynamicArenaAllocator allocator;
	MirRegisterID currentReg;
	MirBlockIdx currentBlock;
	List{MirOperand} bindings; // Indexed by SymbolIdx
}


fn void MirGenerator.init(MirGenerator* this, ProgramAst* inputAst, SymbolTable* symbolTable)
{
	this.inputAst = inputAst;
	this.symbolTable = symbolTable;

	this.allocator = {};
	this.allocator.init(mem, 1024);

	this.output = {};
	this.currentReg = 0;
	this.currentBlock = 0;

	this.output.init(&this.allocator, 1024);
	this.bindings.init(&this.allocator, this.symbolTable.symbols.len());

	common::list_append_fill{MirOperand}(&this.bindings, placeHolderOperand, this.symbolTable.symbols.len());
}

fn void MirGenerator.deinit(MirGenerator* this)
{
	this.allocator.free();
}

fn MirGenResult MirGenerator.run(MirGenerator* this)
{

	foreach(idx, &decl : this.inputAst.declarations){
	    assert(idx < int::max);
	    int intIdx = (int)idx;
		if(decl.kind == DeclKind.FUNCTION){
			this.lower_fun(decl, intIdx);
		}
	}

	return MirGenResult.OK;
}

fn void MirGenerator.lower_fun(MirGenerator* this, Decl* decl, DeclIdx index)
{
	debug::@log_mir("lowering func: '%s'", this.inputAst.names[decl.fnDecl.nameIdx].src_text());

	// clear out all temporaries and operands 
	common::list_set_values{MirOperand}(&this.bindings, placeHolderOperand);

	Stmt funcBody = this.inputAst.statements[decl.fnDecl.body];
	BlockStmt bodyBlock = funcBody.blockStmt;

	MirFunction loweredFunc = {.sourceDeclIdx = index};
	loweredFunc.blocksStart = this.blocks_len();

	// Parameters behave like pre-existing locals at function entry.
	DeclParamRange paramRange = this.symbolTable.declParamRanges[index];
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
	loweredFunc.blocksEnd = this.blocks_len();

	this.output.functions.push(loweredFunc);
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
	debug::@log_mir("lowering var decl: '%s'", this.inputAst.names[stmt.varDecl.nameIdx].src_text());

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
	debug::@log_mir("lowering var init: '%s'", this.inputAst.names[stmt.varDecl.nameIdx].src_text());

	CompTypeInfo storeType = this.symbolTable.exprTypes[stmt.varDecl.init];
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
		case ExprKind.STRING_LITERAL:	
		{
			InternedString srcString = this.inputAst.names[expr.stringLiteral];
			InternedString allocatedConstantString = globals::constantStrings.get_or_intern(srcString.src_text());
			return {.kind = MirOperandKind.IMM_STRING, 	.immString = allocatedConstantString};
		}
		case ExprKind.BINARY:
		{
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
		}
		case ExprKind.CALL:
		{
			CallTarget target = this.symbolTable.callTargets[exprIdx];
			assert(target.kind == CallTargetKind.FREE_FUN);
			return this.lower_free_fun(exprIdx);
		}
        case ExprKind.VAR:
		{
			SymbolIdx varExprSymbolIdx = this.symbolTable.exprSymbols[exprIdx];
			CompTypeInfo varExprType = this.symbolTable.exprTypes[exprIdx];
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
		}
		case ExprKind.MEMBER:
		{
			// Basically the same as VAR but we lower the place since we know it's a member
			CompTypeInfo memberType = this.symbolTable.exprTypes[exprIdx];
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
		}
		default:{
			unreachable();
		}
	}

}

fn MirOperand MirGenerator.lower_free_fun(MirGenerator* this, ExprIdx callExprIdx)
{
	Expr* callExpr = &this.inputAst.expressions[callExprIdx];
	MirRegisterID resultReg = this.currentReg++;

	CallTarget target = this.symbolTable.callTargets[callExprIdx];
	assert(target.kind == CallTargetKind.FREE_FUN);

	DeclIdx fnDeclIdx = target.fnDeclIdx;
	MirOperand callee = {.kind = MirOperandKind.FUNCTION, .fnCalleeIdx = fnDeclIdx};

	List{MirOperand} callOperands = {};
	sz operandCount = (sz)callExpr.call.argsEnd - callExpr.call.argsStart + 2;
	callOperands.init(&this.allocator, operandCount);
	callOperands.push(callee);

	// Receiver is inserted as arg0 for method calls lowered to free functions.
	ExprIdx receiverExprIdx = this.symbolTable.callReceiverExpr[callExprIdx];

	if (receiverExprIdx != parser::NO_IDX) {
		MirOperand receiver = this.lower_expr(receiverExprIdx);
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
		.type = this.symbolTable.exprTypes[callExprIdx],
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
		case ExprKind.VAR:
		{
			SymbolIdx symbolIdx = this.symbolTable.exprSymbols[exprIdx];
			assert(symbolIdx < this.bindings.len());
			MirOperand place = this.bindings[symbolIdx];
			assert(place.kind == MirOperandKind.PLACE);
			return place;
		}
		case ExprKind.MEMBER:
		{
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
		}
		default:
		{
			unreachable("Unsupported lvalue expression in lower_place");
		}
	}

}

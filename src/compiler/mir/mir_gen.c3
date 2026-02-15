module mir;

import parser;
import log;
import debug;
import common;
import std::collections::list;

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

	common::list_fill{MirOperand}(&this.bindings, placeHolderOperand, this.symbolTable.symbols.len());

}

fn void MirGenerator.deinit(MirGenerator* this)
{
	this.allocator.free();
}

fn void MirGenerator.run(MirGenerator* this)
{

	foreach(idx, &decl : this.inputAst.declarations){
		if(decl.kind == DeclKind.FUNCTION){
			this.lower_fun(decl, idx);
		}
	}

	this.output.print(this.inputAst, this.symbolTable);
}

fn void MirGenerator.lower_fun(MirGenerator* this, Decl* decl, DeclIdx index)
{
	debug::@log_mir("lowering func: '%s'", this.inputAst.names[decl.fnDecl.nameIdx]);

	// clear out all temporaries and operands 
	common::list_set_values{MirOperand}(&this.bindings, placeHolderOperand);

	Stmt funcBody = this.inputAst.statements[decl.fnDecl.body];
	BlockStmt bodyBlock = funcBody.blockStmt;

	MirFunction loweredFunc = {.sourceDeclIdx = index};
	loweredFunc.blocksStart = this.output.blocks.len();

	MirBlockIdx blockIdx = this.output.blocks.len();
	MirBlock block = {
		.idx = blockIdx,
		.instructionsStart = this.output.instructions.len(),
		.instructionsEnd = this.output.instructions.len(),
		.terminator = NO_TERMINATOR,
	};
	this.output.blocks.push(block);
	this.currentBlock = blockIdx;

	foreach(stmtIdx : bodyBlock.stmts){
		this.lower_stmt(stmtIdx);
	}

	MirBlock* loweredBlock = &this.output.blocks[blockIdx];
	loweredBlock.instructionsEnd = this.output.instructions.len();
	if (loweredBlock.terminator == NO_TERMINATOR) {
		MirTerminator defaultTerm = {
			.opCode = MirTerminatorOp.RETURN,
			.operandsStart = this.output.operands.len(),
			.operandsEnd = this.output.operands.len(),
		};
		loweredBlock.terminator = this.output.terminators.len();
		this.output.terminators.push(defaultTerm);
	}
	loweredFunc.blocksEnd = loweredFunc.blocksStart + 1;

	this.output.functions.push(loweredFunc);
}

fn void MirGenerator.lower_stmt(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	debug::@log_mir("lowering stmt: '%s'", stmt.kind);

	switch(stmt.kind)
	{
		case StmtKind.DECL:		this.lower_var_decl(stmtIdx);
		case StmtKind.RETURN:	this.lower_return(stmtIdx);
		case StmtKind.EXPR:		this.lower_expr(stmt.exprStmt);
		default: 				break;
	}
}


fn void MirGenerator.lower_var_decl(MirGenerator* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	debug::@log_mir("lowering var decl: '%s'", this.inputAst.names[stmt.varDecl.nameIdx]);
	if (stmt.varDecl.init == parser::NO_IDX) {
		return;
	}
	MirOperand initValue = this.lower_expr(stmt.varDecl.init);

	MirPlaceIdx placeIdx = this.output.places.len();
	MirPlace place = {.idx = placeIdx, .sourceNameIdx = stmt.varDecl.nameIdx};
	this.output.places.push(place);

	OperandIdx start = this.output.operands.len();
	this.output.operands.push(initValue);
	this.output.operands.push({.kind = MirOperandKind.PLACE, .as.placeIdx = placeIdx});
	OperandIdx end = this.output.operands.len();

	SymbolIdx stmtSymbolIdx = this.symbolTable.stmtSymbols[stmtIdx];
	CompTypeInfo storeType = this.symbolTable.exprTypes[stmt.varDecl.init];
	if (stmtSymbolIdx < this.symbolTable.symbols.len()) {
		storeType = this.symbolTable.symbols[stmtSymbolIdx].type;
	}

	this.bindings[stmtSymbolIdx] = initValue;

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
	debug::@log_mir("lowering return: '%s'", this.inputAst.names[stmt.varDecl.nameIdx]);
	OperandIdx start = this.output.operands.len();

	if (stmt.retStmt.value != parser::NO_IDX) {
		MirOperand returnValue = this.lower_expr(stmt.retStmt.value);
		this.output.operands.push(returnValue);
	}
	OperandIdx end = this.output.operands.len();

	MirTerminator term = {
		.opCode = MirTerminatorOp.RETURN,
		.operandsStart = start,
		.operandsEnd = end,
	};

	MirTerminatorIdx termIdx = this.output.terminators.len();
	this.output.terminators.push(term);
	this.output.blocks[this.currentBlock].terminator = termIdx;
}

fn MirOperand MirGenerator.lower_expr(MirGenerator* this, ExprIdx exprIdx)
{
	Expr* expr = &this.inputAst.expressions[exprIdx];
	debug::@log_mir("lowering expr: '%s'", expr.kind);

	switch (expr.kind)
	{
		case ExprKind.INT:				return {.kind = MirOperandKind.IMM_INT, 	.as.immInt = expr.intLiteral};
		case ExprKind.FLOAT:			return {.kind = MirOperandKind.IMM_FLOAT, 	.as.immFloat = expr.floatLiteral};
		case ExprKind.DOUBLE:			return {.kind = MirOperandKind.IMM_DOUBLE, 	.as.immDouble = expr.doubleLiteral};
		case ExprKind.BOOL:				return {.kind = MirOperandKind.IMM_BOOL, 	.as.immBool = expr.boolLiteral};
		case ExprKind.NULL:				return {.kind = MirOperandKind.IMM_NULL, 	.as.immInt = 0};
	
		case ExprKind.BINARY:
		{
			MirOperand lhs = this.lower_expr(expr.binary.lhs);
			MirOperand rhs = this.lower_expr(expr.binary.rhs);
			MirRegisterID resultReg = this.currentReg++;
			OperandIdx start = this.output.operands.len();
			this.output.operands.push(lhs);
			this.output.operands.push(rhs);

			OperandIdx end = this.output.operands.len();
			MirInstruction inst = {
				.opCode = ast_to_mir_op(expr.binary.op),
				.type = this.symbolTable.exprTypes[exprIdx],
				.result = resultReg,
				.operandsStart = start,
				.operandsEnd = end,
				.sourceExprIdx = exprIdx,
			};
			this.output.instructions.push(inst);
			return {.kind = MirOperandKind.REGISTER, .as.regId = resultReg};
		}
		case ExprKind.CALL:
		{
			CallTarget target = this.symbolTable.callTargets[exprIdx];
			switch (target.kind){
				case CallTargetKind.FREE_FUN: return this.lower_free_fun(exprIdx);
				case CallTargetKind.METHOD:   return this.lower_method(exprIdx);
				default:                      return this.lower_free_fun(exprIdx);
			}
		}
		case ExprKind.VAR:
		{
			SymbolIdx varExprSymbolIdx = this.symbolTable.exprSymbols[exprIdx];
			MirOperand variable = this.bindings[varExprSymbolIdx];
			return variable;
		}
		default:
			return {.kind = MirOperandKind.REGISTER, .as.regId = NO_REG};
	}

}

fn MirOperand MirGenerator.lower_free_fun(MirGenerator* this, ExprIdx callExprIdx)
{
	Expr* callExpr = &this.inputAst.expressions[callExprIdx];
	MirRegisterID resultReg = this.currentReg++;
	OperandIdx start = this.output.operands.len();

	CallTarget target = this.symbolTable.callTargets[callExprIdx];
	assert(target.kind == CallTargetKind.FREE_FUN);

	DeclIdx fnDeclIdx = target.fnDeclIdx;
	MirOperand callee = {.kind = MirOperandKind.FUNCTION, .as.fnCalleeIdx = fnDeclIdx};
	this.output.operands.push(callee);

	for(ExprIdx i = callExpr.call.argsStart; i < callExpr.call.argsEnd; i++){
		MirOperand arg = this.lower_expr(this.inputAst.args[i]);
		this.output.operands.push(arg);
	}

	OperandIdx end = this.output.operands.len();
	MirInstruction inst = {
		.opCode = MirOpCode.CALL,
		.type = this.symbolTable.exprTypes[callExprIdx],
		.result = resultReg,
		.operandsStart = start,
		.operandsEnd = end,
		.sourceExprIdx = callExprIdx,
	};
	this.output.instructions.push(inst);
	return {.kind = MirOperandKind.REGISTER, .as.regId = resultReg};
}


fn MirOperand MirGenerator.lower_method(MirGenerator* this, ExprIdx callExprIdx)
{
	Expr* callExpr = &this.inputAst.expressions[callExprIdx];
	MirRegisterID resultReg = this.currentReg++;
	OperandIdx start = this.output.operands.len();

	// Methods currently use a separate (structDeclIdx, methodIdx) target space.
	// Keep the callee placeholder for now, and encode receiver as arg0.
	this.output.operands.push({.kind = MirOperandKind.FUNCTION, .as.fnCalleeIdx = parser::NO_IDX});

	ExprIdx receiverExprIdx = callExpr.call.memberCaller;
	if (receiverExprIdx == parser::NO_IDX) {
		Expr* calleeExpr = &this.inputAst.expressions[callExpr.call.callee];
		if (calleeExpr.kind == ExprKind.MEMBER) {
			receiverExprIdx = calleeExpr.member.base;
		}
	}

	MirOperand receiver = placeHolderOperand;
	if (receiverExprIdx != parser::NO_IDX) {
		receiver = this.lower_expr(receiverExprIdx);
	}
	this.output.operands.push(receiver);

	for(ExprIdx i = callExpr.call.argsStart; i < callExpr.call.argsEnd; i++){
		MirOperand arg = this.lower_expr(this.inputAst.args[i]);
		this.output.operands.push(arg);
	}

	OperandIdx end = this.output.operands.len();
	MirInstruction inst = {
		.opCode = MirOpCode.CALL,
		.type = this.symbolTable.exprTypes[callExprIdx],
		.result = resultReg,
		.operandsStart = start,
		.operandsEnd = end,
		.sourceExprIdx = callExprIdx,
	};
	this.output.instructions.push(inst);
	return {.kind = MirOperandKind.REGISTER, .as.regId = resultReg};
}

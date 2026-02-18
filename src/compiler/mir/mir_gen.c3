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

	SymbolIdx stmtSymbolIdx = this.symbolTable.stmtSymbols[stmtIdx];
	MirPlace newPlace = {.baseSymbolIdx = stmtSymbolIdx, .projectionIdx = NO_PROJECTION};
	MirPlaceIdx placeIdx = this.push_place_get_idx(&newPlace);
	MirOperand operand = {.kind = MirOperandKind.PLACE, .as.placeIdx = placeIdx};

	this.bindings[stmtSymbolIdx] = operand;
	if (stmt.varDecl.init != parser::NO_IDX) {
		this.lower_var_init(stmtIdx, stmtSymbolIdx);
	}
}


fn void MirGenerator.lower_var_init(MirGenerator* this, StmtIdx stmtIdx, SymbolIdx stmtSymbolIdx)
{

	Stmt* stmt = &this.inputAst.statements[stmtIdx];
	debug::@log_mir("lowering var init: '%s'", this.inputAst.names[stmt.varDecl.nameIdx]);

	CompTypeInfo storeType = this.symbolTable.exprTypes[stmt.varDecl.init];
	if (stmtSymbolIdx < this.symbolTable.symbols.len()) {
		storeType = this.symbolTable.symbols[stmtSymbolIdx].type;
	}
	MirOperand initValue = this.lower_expr(stmt.varDecl.init);
	MirOperand placeOperand = this.bindings[stmtSymbolIdx];
	OperandIdx start = this.output.operands.len();
	this.output.operands.push(placeOperand);
	this.output.operands.push(initValue);
	OperandIdx end = this.output.operands.len();


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
			OperandIdx start = this.output.operands.len();
			this.output.operands.push(lhs);
			this.output.operands.push(rhs);

			OperandIdx end = this.output.operands.len();
			MirInstruction inst = {
				.opCode = opCode,
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
			assert(target.kind == CallTargetKind.FREE_FUN);
			return this.lower_free_fun(exprIdx);
		}
		case ExprKind.VAR:
		{

			SymbolIdx varExprSymbolIdx = this.symbolTable.exprSymbols[exprIdx];
			CompTypeInfo varExprType = this.symbolTable.exprTypes[exprIdx];
			MirOperand place = this.bindings[varExprSymbolIdx];
			assert(place.kind == MirOperandKind.PLACE);
			MirRegisterID resultReg = this.currentReg++;
			OperandIdx start = this.output.operands.len();
			this.output.operands.push(place);
			OperandIdx end = this.output.operands.len();

			MirInstruction inst = {
				.opCode = MirOpCode.LOAD,
				.type = varExprType,
				.result = resultReg,
				.operandsStart = start,
				.operandsEnd = end,
				.sourceExprIdx = exprIdx,
			};
			this.output.instructions.push(inst);
			return {.kind = MirOperandKind.REGISTER, .as.regId = resultReg};
		}
		default:{
			return {.kind = MirOperandKind.REGISTER, .as.regId = NO_REG};
		}
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

	// Receiver is inserted as arg0 for method calls lowered to free functions.
	ExprIdx receiverExprIdx = this.symbolTable.callReceiverExpr[callExprIdx];

	if (receiverExprIdx != parser::NO_IDX) {
		MirOperand receiver = this.lower_expr(receiverExprIdx);
		this.output.operands.push(receiver);
	} 

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
			MirPlace basePlace = this.output.places[basePlaceOperand.as.placeIdx];

			// Each projection is part of a chain str.foo.bar.x
			//										   ↑   ↑  ↑_ stores index to 'bar'
			//										   |   |_ stores index to 'foo'
			//										   |_ index is NO_PROJECTION
			// Projection chains are stored backwards: newest node points to previous one.
			// This lets places share common prefixes (e.g. `a.x` reused by `a.x.y`).
			MirProjection projection = {
				.fieldIdx = expr.member.memberIdx,
				.prevProjectionIdx = basePlace.projectionIdx,
			};
			MirProjectionIdx projectionIdx = this.push_projection_get_idx(&projection);

			MirPlace memberPlace = {
				.baseSymbolIdx = basePlace.baseSymbolIdx,
				.projectionIdx = projectionIdx,
			};
			MirPlaceIdx placeIdx = this.push_place_get_idx(&memberPlace);
			return {.kind = MirOperandKind.PLACE, .as.placeIdx = placeIdx};
		}
		default:
		{
			unreachable("Unsupported lvalue expression in lower_place");
		}
	}

}

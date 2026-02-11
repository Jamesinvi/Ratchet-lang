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
			MirRegisterID resultReg = this.currentReg++;
			OperandIdx start = this.output.operands.len();
			ExprIdx calleeIdx = expr.call.callee;
			SymbolIdx calleeSymbolIdx = this.symbolTable.exprSymbols[calleeIdx];
			Symbol calleeSymbol = this.symbolTable.symbols[calleeSymbolIdx];
			MirOperand callee = {.kind = MirOperandKind.FUNCTION, .as.fnCalleeIdx = (DeclIdx)calleeSymbol.idx};
			this.output.operands.push(callee);
			for(ExprIdx i = expr.call.argsStart; i < expr.call.argsEnd;i++){
				MirOperand arg = this.lower_expr(this.inputAst.args[i]);
				this.output.operands.push(arg);
			}
			OperandIdx end = this.output.operands.len();
			MirInstruction inst = {
				.opCode = MirOpCode.CALL,
				.type = this.symbolTable.exprTypes[exprIdx],
				.result = resultReg,
				.operandsStart = start,
				.operandsEnd = end,
				.sourceExprIdx = exprIdx,
			};
			this.output.instructions.push(inst);
			return {.kind = MirOperandKind.REGISTER, .as.regId = resultReg};
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




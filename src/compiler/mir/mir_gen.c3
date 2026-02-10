module mir;

import parser;
import log;
import debug;
import common;

struct MirGenerator
{
	ProgramAst* inputAst;
	SymbolTable* symbols;
	MirProgram output;
	DynamicArenaAllocator allocator;
	MirRegisterID currentReg;
	MirBlockIdx currentBlock;
}


fn void MirGenerator.init(MirGenerator* this, ProgramAst* inputAst, SymbolTable* symbols)
{
	this.inputAst = inputAst;
	this.symbols = symbols;

	this.allocator = {};
	this.allocator.init(mem, 1024);

	this.output = {};
	this.currentReg = 0;
	this.currentBlock = 0;

	this.output.init(&this.allocator, 1024);

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

	this.output.print(this.inputAst, this.symbols);
}

fn void MirGenerator.lower_fun(MirGenerator* this, Decl* decl, DeclIdx index)
{
	debug::@log_mir("lowering func: '%s'", this.inputAst.names[decl.fnDecl.nameIdx]);

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

	SymbolIdx stmtSymbolIdx = this.symbols.stmtSymbols[stmtIdx];
	CompTypeInfo storeType = this.symbols.exprTypes[stmt.varDecl.init];
	if (stmtSymbolIdx < this.symbols.symbols.len()) {
		storeType = this.symbols.symbols[stmtSymbolIdx].type;
	}

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
	debug::@log_mir("lowering expr: '%s'", exprIdx);

	switch (expr.kind)
	{
		case ExprKind.INT:				return {.kind = MirOperandKind.IMM_INT, 	.as.immInt = expr.intLiteral};
		case ExprKind.FLOAT:			return {.kind = MirOperandKind.IMM_FLOAT, 	.as.immFloat = expr.floatLiteral};
		case ExprKind.DOUBLE:			return {.kind = MirOperandKind.IMM_DOUBLE, 	.as.immDouble = expr.doubleLiteral};
		case ExprKind.BOOL:				return {.kind = MirOperandKind.IMM_BOOL, 	.as.immBool = expr.boolLiteral};
	
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
				.opCode = MirOpCode.ADD,
				.type = this.symbols.exprTypes[exprIdx],
				.result = resultReg,
				.operandsStart = start,
				.operandsEnd = end,
				.sourceExprIdx = exprIdx,
			};
			this.output.instructions.push(inst);
			return {.kind = MirOperandKind.REGISTER, .as.regId = resultReg};
		}
		default:
			return {.kind = MirOperandKind.REGISTER, .as.regId = NO_REG};
	}

}




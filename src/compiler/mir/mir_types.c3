module mir;
import parser;
import common;
import std::collections::list;
import log;

alias MirRegisterID = int;
alias MirBlockIdx = usz;
alias MirPlaceIdx = usz;
alias MirProjectionIdx = usz;
alias MirInstructionIdx = usz;
alias MirTerminatorIdx = usz;
alias OperandIdx = usz;

const NO_REG = -1;
const NO_TERMINATOR = usz.max;
const NO_PROJECTION = usz.max;

bitstruct MirRegisterFlags : char
{
	bool isConst;
	bool isParam;

}

struct MirRegister
{
	CompTypeInfo 		type;
	MirRegisterID 		id;
	MirRegisterFlags	flags;
}

enum MirOpCode : char (String asStr)
{
	ADD			= "add",
	SUB			= "sub",
	MUL 		= "mul",
	DIV 		= "div",
	EQ 			= "eq",
	NEQ 		= "noteq",
	LESS 		= "less",
	LESS_EQ		= "lesseq",
	GREATER 	= "greater",
	GREATER_EQ 	= "greatereq",
	AND 		= "and",
	OR 			= "or",
	AS 			= "as",
	STORE 		= "store",
	CALL  		= "call",
	LOAD 		= "load",
}

enum MirTerminatorOp : char (String asStr)
{
	JUMP		= "jump",
	BRANCH		= "branch",
	RETURN 		= "return",
}

enum MirOperandKind : char (String asStr)
{
	INVALID		= "invalid!",
	REGISTER 	= "reg",
	PLACE 		= "place",
	IMM_INT 	= "imm_i",
	IMM_FLOAT 	= "imm_f",
	IMM_DOUBLE  = "imm_d",
	IMM_BOOL 	= "imm_b",
	IMM_NULL 	= "null",
	BLOCK 		= "block",
	FUNCTION 	= "fn",
}


struct MirOperand
{
	MirOperandKind kind;
	union as {
		MirRegisterID 	regId;
		MirPlaceIdx 	placeIdx;
		DeclIdx 		fnCalleeIdx;
		int 			immInt;
		float 			immFloat;
		double 			immDouble;
		bool 			immBool;
	}
}

struct MirInstruction
{
	OperandIdx operandsStart;
	OperandIdx operandsEnd;
	union {
 		ExprIdx sourceExprIdx;
 		StmtIdx sourceStmtIdx;
	}
	MirRegisterID result;
	MirOpCode opCode;
	CompTypeInfo type;
}

struct MirPlace
{
	usz idx;
	SymbolIdx baseSymbolIdx;
	MirProjectionIdx projectionIdx;
}

struct MirProjection
{
	NameIdx fieldIdx;
	MirProjectionIdx prevProjectionIdx;		// Each projection stores index to previous projection in the chain (NO_PROJECTION for first projection!)
}

struct MirTerminator
{
	MirTerminatorOp opCode;
	OperandIdx operandsStart;
	OperandIdx operandsEnd;
}

struct MirBlock
{
	MirBlockIdx idx;
	MirInstructionIdx instructionsStart;
	MirInstructionIdx instructionsEnd;
	MirTerminatorIdx terminator;
}

struct MirFunction
{
	usz blocksStart;
	usz blocksEnd;
	DeclIdx sourceDeclIdx;
}

struct MirProgram
{
	List{MirFunction} functions;
	List{MirInstruction} instructions;
	List{MirTerminator} terminators;
	List{MirBlock} blocks;
	List{MirPlace} places;
	List{MirProjection} projections;
	List{MirOperand} operands;
}

fn void MirProgram.init(MirProgram* this, Allocator allocator, usz size)
{
	this.functions.init(allocator, size);
	this.instructions.init(allocator, size);
	this.terminators.init(allocator, size);
	this.blocks.init(allocator, size);
	this.places.init(allocator, size);
	this.projections.init(allocator, size);
	this.operands.init(allocator, size);
}


fn void MirProgram.print(MirProgram* this, ProgramAst* ast, SymbolTable* symbols)
{
	log::logn("------------ MIR ------------");
	foreach(fun : this.functions)
	{
		if (fun.sourceDeclIdx >= ast.declarations.len() || ast.declarations[fun.sourceDeclIdx].kind != DeclKind.FUNCTION) {
			log::logn("function <invalid>");
			continue;
		}
		FnDeclAst* funDecl = &ast.declarations[fun.sourceDeclIdx].fnDecl;
		SymbolIdx symbolIdx = symbols.declSymbols[fun.sourceDeclIdx];
		if (symbolIdx < symbols.symbols.len()) {
			Symbol funSymbol = symbols.symbols[symbolIdx];
			log::log("function ");
			this.print_decl_function_name(fun.sourceDeclIdx, ast);
			log::logn(" -> %s", funSymbol.type.type);
		} else {
			log::log("function ");
			this.print_decl_function_name(fun.sourceDeclIdx, ast);
			log::logn(" -> %s", ast.names[funDecl.returnType.nameIdx]);
		}
		for(usz i = fun.blocksStart; i < fun.blocksEnd; i++){
			this.print_block(this.blocks[i], ast);
		}
	}
	log::logn("-----------------------------");
}

fn void MirProgram.print_decl_function_name(MirProgram* this, DeclIdx declIdx, ProgramAst* ast)
{
	if (declIdx >= ast.declarations.len() || ast.declarations[declIdx].kind != DeclKind.FUNCTION) {
		log::log("<fn?>");
		return;
	}
	FnDeclAst* fnDecl = &ast.declarations[declIdx].fnDecl;
	if (fnDecl.params.len() > 0 && fnDecl.params[0].type.tokenType == TokenType.THIS) {
		String structName = ast.names[fnDecl.params[0].type.nameIdx];
		String methodName = ast.names[fnDecl.nameIdx];
		log::log("%s.%s", structName, methodName);
		return;
	}
	log::log("%s", ast.names[fnDecl.nameIdx]);
}


fn void MirProgram.print_operand(MirProgram* this, MirOperand op, ProgramAst* ast)
{
	switch (op.kind){
		case MirOperandKind.REGISTER:
			if (op.as.regId == NO_REG) {
				log::log("<noreg>");
			} else {
				log::log("_r%s", op.as.regId);
			}
		case MirOperandKind.PLACE:							log::log("_%%%s", op.as.placeIdx);
		case MirOperandKind.IMM_INT:						log::log("%s", op.as.immInt);
		case MirOperandKind.IMM_FLOAT:						log::log("%s", op.as.immFloat);
		case MirOperandKind.IMM_DOUBLE:						log::log("%s", op.as.immDouble);
		case MirOperandKind.IMM_BOOL:						log::log("%s", op.as.immBool);
		case MirOperandKind.IMM_NULL:						log::log("null");
		case MirOperandKind.BLOCK:							log::log("block_%s", op.as.placeIdx);
		case MirOperandKind.FUNCTION:
		{
			DeclIdx declIdx = op.as.fnCalleeIdx;
			this.print_decl_function_name(declIdx, ast);
		}
		default:
			log::log("<?>");
	}
}

fn void MirProgram.print_instruction(MirProgram* this, MirInstruction inst, ProgramAst* ast)
{
	log::log("  ");
	if (inst.result != NO_REG) {
		log::log("_r%s = ", inst.result);
	}
	log::log("%s %s", inst.opCode.asStr, inst.type.type);
	if (inst.operandsStart < inst.operandsEnd) {
		log::log(" ");
	}
	for (usz opIdx = inst.operandsStart; opIdx < inst.operandsEnd; opIdx++){
		if (opIdx > inst.operandsStart) {
			log::log(", ");
		}
		if (opIdx >= this.operands.len()) {
			log::log("<bad-op-idx:%s>", opIdx);
			continue;
		}
		this.print_operand(this.operands[opIdx], ast);
	}
	log::logn("");
}

fn void MirProgram.print_terminator(MirProgram* this, MirTerminator term, ProgramAst* ast)
{
	String termName = term.opCode.asStr;
	log::log("  %s", termName);
	if (term.operandsStart < term.operandsEnd) {
		log::log(" ");
	}
	for (usz opIdx = term.operandsStart; opIdx < term.operandsEnd; opIdx++){
		if (opIdx > term.operandsStart) {
			log::log(", ");
		}
		if (opIdx >= this.operands.len()) {
			log::log("<bad-op-idx:%s>", opIdx);
			continue;
		}
		this.print_operand(this.operands[opIdx], ast);
	}
	log::logn("");
}

fn void MirProgram.print_block(MirProgram* this, MirBlock block, ProgramAst* ast)
{
	if(block.idx == 0){
		log::logn("start:");
	}else{
		log::logn("block_%s:", block.idx);
	}

	for (usz i = block.instructionsStart; i < block.instructionsEnd; i++){
		if (i >= this.instructions.len()) {
			log::logn("  <bad-inst-idx:%s>", i);
			continue;
		}
		this.print_instruction(this.instructions[i], ast);
	}

	if (block.terminator == NO_TERMINATOR || block.terminator >= this.terminators.len()) {
		log::logn("  <no terminator>");
		return;
	}

	this.print_terminator(this.terminators[block.terminator], ast);
}


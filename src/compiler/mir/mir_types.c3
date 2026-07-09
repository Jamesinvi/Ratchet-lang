module compiler::mir;
import compiler;
import common;
import std::collections::list;
import log;

alias MirRegisterID = int;
alias MirBlockIdx = int;
alias MirPlaceIdx = int;
alias MirProjectionIdx = int;
alias MirInstructionIdx = int;
alias MirTerminatorIdx = int;
alias OperandIdx = int;

const NO_REG = -1;
const NO_TERMINATOR = -1;
const NO_PROJECTION = -1;
const NO_BLOCK = -1;

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
	ADD			{ "add" },
	SUB			{ "sub" },
	MUL 		{ "mul" },
	DIV 		{ "div" },
	EQ 			{ "eq" },
	NEQ 		{ "noteq" },
	LESS 		{ "less" },
	LESS_EQ		{ "lesseq" },
	GREATER 	{ "greater" },
	GREATER_EQ 	{ "greatereq" },
	AND 		{ "and" },
	OR 			{ "or" },
	AS 			{ "as" },
	STORE 		{ "store" },
	CALL  		{ "call" },
	LOAD 		{ "load" },
	ECHO 		{ "echo" },
}

enum MirTerminatorOp : char (String asStr)
{
	JUMP		{ "jump" },
	BRANCH		{ "branch" },
	RETURN 		{ "return" },
}

enum MirOperandKind : char (String asStr)
{
	INVALID		{ "invalid!" },
	REGISTER 	{ "reg" },
	PLACE 		{ "place" },
	IMM_INT 	{ "imm_i" },
	IMM_FLOAT 	{ "imm_f" },
	IMM_DOUBLE  { "imm_d" },
	IMM_BOOL 	{ "imm_b" },
	IMM_NULL 	{ "null" },
	BLOCK 		{ "block" },
	FUNCTION 	{ "fn" },
}


struct MirOperand
{
	union {
		MirRegisterID 	regId;
		MirPlaceIdx 	placeIdx;
		MirBlockIdx 	blockIdx;
		DeclIdx 		fnCalleeIdx;
		int 			immInt;
		float 			immFloat;
		double 			immDouble;
		bool 			immBool;
	}
	MirOperandKind kind;
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
	int idx;
	SymbolIdx baseSymbolIdx;
	MirProjectionIdx projectionIdx;
}

struct MirProjection
{
	int fieldIdx;
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
	MirBlockIdx blocksStart;
	MirBlockIdx blocksEnd;
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

fn void MirProgram.init(MirProgram* this, Allocator allocator, sz size)
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
			log::logn(" -> %s", ast.names[funDecl.returnType.nameIdx].text());
		}
		for(sz i = fun.blocksStart; i < fun.blocksEnd; i++){
			this.print_block(this.blocks[i], ast);
		}
		log::log("\n");
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
		InternedString structName = ast.names[fnDecl.params[0].type.nameIdx];
		InternedString methodName = ast.names[fnDecl.nameIdx];
		log::log("%s.%s", structName.text(), methodName.text());
		return;
	}
	log::log("%s", ast.names[fnDecl.nameIdx].text());
}


fn void MirProgram.print_operand(MirProgram* this, MirOperand op, ProgramAst* ast)
{
	switch (op.kind){
		case MirOperandKind.REGISTER:
			if (op.regId == NO_REG) {
				log::log("<noreg>");
			} else {
				log::log("_r%s", op.regId);
			}
		case MirOperandKind.IMM_INT:						log::log("%s", 		op.immInt);
		case MirOperandKind.IMM_FLOAT:						log::log("%s", 		op.immFloat);
		case MirOperandKind.IMM_DOUBLE:						log::log("%s", 		op.immDouble);
		case MirOperandKind.IMM_BOOL:						log::log("%s", 		op.immBool);
		case MirOperandKind.IMM_NULL:						log::log("null");
		case MirOperandKind.BLOCK:							log::log("block_%s",op.blockIdx);
		case MirOperandKind.FUNCTION:
		{
			DeclIdx declIdx = op.fnCalleeIdx;
			this.print_decl_function_name(declIdx, ast);
		}
		case MirOperandKind.PLACE:					
		{
			MirPlace* place = &this.places[op.placeIdx];
			if(place.projectionIdx == NO_PROJECTION){
				log::log("_%s", place.baseSymbolIdx);
				return;
			}
			MirProjection* projection = &this.projections[place.projectionIdx];
			log::log("_%s_@fieldIdx:%s", place.baseSymbolIdx, projection.fieldIdx);
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
	for (sz opIdx = inst.operandsStart; opIdx < inst.operandsEnd; opIdx++){
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
	for (sz opIdx = term.operandsStart; opIdx < term.operandsEnd; opIdx++){
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

	for (sz i = block.instructionsStart; i < block.instructionsEnd; i++){
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

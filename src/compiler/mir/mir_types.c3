module mir;
import parser;
import std::collections::list;
import log;

alias MirRegisterID = int;
alias MirBlockIdx = usz;
alias MirPlaceIdx = usz;
alias MirInstructionIdx = usz;
alias MirTerminatorIdx = usz;
alias OperandIdx = usz;
const NO_REG = -1;
const NO_TERMINATOR = usz.max;

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

enum MirOpCode : char
{
	ADD,
	SUB,
	MUL,
	DIV,
	LOAD,
	STORE,
}

enum MirTerminatorOp : char
{
	JUMP,
	BRANCH,
	RETURN,
}

enum MirOperandKind : char
{
	REGISTER,
	PLACE,
	IMM_INT,
	IMM_FLOAT,
	IMM_DOUBLE,
	IMM_BOOL,
	BLOCK,
}


struct MirOperand
{
	MirOperandKind kind;
	union as {
		MirRegisterID 	regId;
		MirPlaceIdx 	placeIdx;
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
	NameIdx sourceNameIdx;
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
	List{MirOperand} operands;
}

fn void MirProgram.init(MirProgram* this, Allocator allocator, usz size)
{
	this.functions.init(allocator, size);
	this.instructions.init(allocator, size);
	this.terminators.init(allocator, size);
	this.blocks.init(allocator, size);
	this.places.init(allocator, size);
	this.operands.init(allocator, size);
}


fn void MirProgram.print(MirProgram* this, ProgramAst* ast, SymbolTable* symbols)
{
	foreach(fun : this.functions)
	{
		FnDeclAst* funDecl = &ast.declarations[fun.sourceDeclIdx].fnDecl;
		SymbolIdx symbolIdx =  symbols.declSymbols[fun.sourceDeclIdx];
		Symbol funSymbol = symbols.symbols[symbolIdx];
		log::logn("function %s -> %s", ast.names[funDecl.nameIdx], funSymbol.type.type);
		for(usz i = fun.blocksStart; i < fun.blocksEnd; i++){
			this.print_block(this.blocks[i]);
		}
	}

}


fn void MirProgram.print_block(MirProgram* this, MirBlock block)
{
	if(block.idx == 0){
		log::logn("start:");
	}else{
		log::logn("block_%s:", block.idx);
	}

	for (usz i = block.instructionsStart; i < block.instructionsEnd; i++){
		MirInstruction inst = this.instructions[i];
		log::log("  ");
		if (inst.result != NO_REG) {
			log::log("_r%s = ", inst.result);
		}
		log::log("%s %s ", inst.opCode, inst.type.type);
		for (usz opIdx = inst.operandsStart; opIdx < inst.operandsEnd; opIdx++){
			if (opIdx > inst.operandsStart) {
				log::log(", ");
			}
			MirOperand op = this.operands[opIdx];
			switch (op.kind){
				case MirOperandKind.REGISTER:	log::log("_r%s", op.as.regId);
				case MirOperandKind.PLACE:		log::log("place_%s", op.as.placeIdx);
				case MirOperandKind.IMM_INT:	log::log("%s", op.as.immInt);
				case MirOperandKind.IMM_BOOL:	log::log("%s", op.as.immBool);
				default:						log::log("<?>");
			}
		}
		log::logn("");
	}

	if (block.terminator == NO_TERMINATOR || block.terminator >= this.terminators.len()) {
		log::logn("  <no terminator>");
		return;
	}

	MirTerminator term = this.terminators[block.terminator];
	log::log("  %s", term.opCode);
	for (usz opIdx = term.operandsStart; opIdx < term.operandsEnd; opIdx++){
		MirOperand op = this.operands[opIdx];
		log::log(" ");
		switch (op.kind){
			case MirOperandKind.REGISTER:	log::log("_r%s", op.as.regId);
			case MirOperandKind.IMM_BOOL:	log::log("%s", op.as.immBool);
			case MirOperandKind.IMM_INT:	log::log("%s", op.as.immInt);
			default:						log::log("<?>");
		}
	}
	log::logn("");
}





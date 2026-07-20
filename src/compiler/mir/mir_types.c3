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
alias MirFunctionIdx = int;
alias OperandIdx = int;

const NO_REG = -1;
const NO_TERMINATOR = -1;
const NO_PROJECTION = -1;
const NO_BLOCK = -1;
const NO_METHOD = -1;
const NO_FUNCTION = -1;

bitstruct MirRegisterFlags : char
{
	bool isConst;
	bool isParam;
}

// Used to track the loop depth, so it's possible to break/continue correctly
struct MirLoopContext
{
	MirBlockIdx continueTarget;
	List{MirTerminatorIdx} breakTargets;
}

struct MirRegister
{
	TypeInfo 		type;
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
	ALLOC_GC	{ "alloc_gc"},
	ZERO_BYTES  { "zero_bytes" }
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
	IMM_STRING	{ "imm_s" },
	IMM_NULL 	{ "null" },
	BLOCK 		{ "block" },
	FUNCTION 	{ "fn" },
}

enum MirPlaceKind : char (String asStr)
{
	FIELD				{ "field" },				// important that this is the default!
	BUILT_IN_REF_VALUE	{ "built_in_ref_value" }	// used for int&.value built-in assignments
}


struct MirOperand
{
	union {
		MirRegisterID 	regId;
		MirPlaceIdx 	placeIdx;
		MirBlockIdx 	blockIdx;
		MirFunctionIdx 	fnCalleeIdx;
		int 			immInt;
		float 			immFloat;
		double 			immDouble;
		bool 			immBool;
		InternedString	immString;
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
	TypeInfo type;
}

struct MirPlace
{
	int idx;
	SymbolIdx baseSymbolIdx;
	MirProjectionIdx projectionIdx;
	MirPlaceKind kind;
	bool isGlobal;
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
	DeclIdx sourceDeclIdx;		// function decl, or owning struct decl for a method
	int sourceMethodIdx;		// NO_METHOD for a free function
	DeclParamRange paramRange;
	TypeInfo returnType;
	SymbolIdx receiverSymbolIdx;	// NO_SYMBOL for a free function
}

struct MirGlobal
{
	SymbolIdx symbolIdx;
	TypeInfo type;
	MirOperand initialValue;
	bool hasInitializer;
}

struct MirProgram
{
	List{MirGlobal} globals;
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
	this.globals.init(allocator, size);
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
	log::logn("globals: ");
	foreach (globalIdx, &global : this.globals) {
		StmtIdx stmtIdx = (StmtIdx)symbols.symbols[global.symbolIdx].idx;
		Stmt* globalDecl = &ast.statements[stmtIdx];
		InternedString name = ast.names[globalDecl.varDecl.nameIdx];
		log::log("  %s %s", ast.names[globalDecl.varDecl.type.nameIdx].text(), name.text());
		if (global.hasInitializer) {
			log::log(" = ");
			this.print_operand(global.initialValue, ast);
		}
		log::logn("");
	}
	log::log("\n");
	foreach(funIdx, &fun : this.functions){
		log::log("function ");
		this.print_function_name((MirFunctionIdx)funIdx, ast);
		log::logn(" -> %s", fun.returnType.type);
		for(sz i = fun.blocksStart; i < fun.blocksEnd; i++){
			this.print_block(this.blocks[i], ast);
		}
		log::log("\n");
	}
	log::logn("-----------------------------");
}

fn void MirProgram.print_function_name(MirProgram* this, MirFunctionIdx functionIdx, ProgramAst* ast)
{
	if (functionIdx < 0 || functionIdx >= this.functions.len()) {
		log::log("<fn?>");
		return;
	}
	MirFunction* function = &this.functions[functionIdx];
	Decl* sourceDecl = &ast.declarations[function.sourceDeclIdx];
	if (function.sourceMethodIdx != NO_METHOD) {
		MethodDeclAst* method = &sourceDecl.structDecl.methods[function.sourceMethodIdx];
		InternedString structName = ast.names[sourceDecl.structDecl.nameIdx];
		InternedString methodName = ast.names[method.nameIdx];
		log::log("%s.%s", structName.text(), methodName.text());
		return;
	}
	log::log("%s", ast.names[sourceDecl.fnDecl.nameIdx].text());
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
		case MirOperandKind.IMM_STRING:						log::log("%s", 		op.immString.text());
		case MirOperandKind.IMM_NULL:						log::log("null");
		case MirOperandKind.BLOCK:							log::log("block_%s",op.blockIdx);
		case MirOperandKind.FUNCTION:
		{
			this.print_function_name(op.fnCalleeIdx, ast);
		}
		case MirOperandKind.PLACE:					
		{
			MirPlace* place = &this.places[op.placeIdx];
			if(place.isGlobal) {
				log::log("global ");
			}
			log::log("in ", place.baseSymbolIdx);

			if(place.kind == MirPlaceKind.BUILT_IN_REF_VALUE){
				log::log("%s", place.kind.asStr);
			}else {
				if(place.projectionIdx == NO_PROJECTION) {
					log::log("_%s", place.baseSymbolIdx);
					return;
				} else {
					MirProjection* projection = &this.projections[place.projectionIdx];
					log::log("%s, _%s_@fieldIdx:%s", place.kind.asStr, place.baseSymbolIdx, projection.fieldIdx);
				}
			}

		
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
	if(inst.type.type == ValueType.REF){
		log::log("->%s", inst.type.refToType);
	}	
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

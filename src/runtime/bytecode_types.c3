module runtime;
import compiler::analyzer;
import std::collections::list;
import common;
import log;

alias BCFunctionIdx = int;
alias BCBlockIdx = int;
alias BCInstructionIdx = int;
alias BCCallInfoIdx = int;
alias BCProjectionIdx = int;
alias BCFrameSlotIdx = int;
alias BCArgIdx = short;

const NO_OFFSET = -1;

const BCInstruction NO_OP = {
	.opCode = BCOpCode.NOP,
	.immKind = BCOperandKind.INVALID,
	.destOffset = NO_OFFSET,
	.leftOffset = NO_OFFSET,
	.rightOffset = NO_OFFSET,
};
	
enum BCOpCode : char (String asStr)
{
	NOP				{ "______" },
	ADDI	        { "add__i" },
	ADDF	        { "add__f" },	
	ADDD	        { "add__d" },
	ADDI_IM			{ "add_ik" },
	INCREMENT		{ "inc__i" },
	SUBI	        { "sub__i" },
	SUBF	        { "sub__f" },
	SUBD	        { "sub__d" },
	MULI	        { "mul__i" },
	MULF	        { "mul__f" },
	MULD	        { "mul__d" },
	DIVI	        { "div__i" },
	DIVF	        { "div__f" },	
	DIVD	        { "div__d" },
	MOVI	        { "mov__i" },
	MOVF	        { "mov__f" },
	MOVD	        { "mov__d" },
	MOVB	        { "mov__b" },
	AND				{ "and__b" },
	OR				{ "or___b" },
	MOV_BYTES	    { "movbts" },
	CONSTI	        { "cnst_i" },
	CONSTF	        { "cnst_f" },
	CONSTD	        { "cnst_d" },
	CONSTB	        { "cnst_b" },
	CONSTS	        { "cnst_s" },
	STORI	        { "stor_i" },
	STORF	        { "stor_f" },
	STORD	        { "stor_d" },
	EQI		        { "eq___i" },
	EQF		        { "eq___f" },
	EQD		        { "eq___d" },
	EQB		        { "eq___b" },
	NEQI	        { "!eq__i" },
	NEQF	        { "!eq__f" },
	NEQD	        { "!eq__d" },
	NEQB	        { "!eq__b" },
	LESSI	        { "less_i" },
	LESSI_IM	    { "lessik" },
	LESSF	        { "less_f" },
	LESSD	        { "less_d" },
	LESS_EQI	    { "leseqi" },
	LESS_EQF	    { "leseqf" },
	LESS_EQD	    { "leseqd" },
	GREATERI        { "grteri" },
	GREATERF        { "grterf" },
	GREATERD        { "grterd" },
	GREATER_EQI     { "gteq_i" },
	GREATER_EQF     { "gteq_f" },
	GREATER_EQD     { "gteq_d" },
	JUMP	        { "jmp___" },
	BRANCH_IF_FALSE	{ "br_nif" },
	CALL  	        { "call__" },
	RETURN 	        { "return" },
	ECHOI           { "echo_i" },
	ECHOF           { "echo_f" },
	ECHOD           { "echo_d" },
	ECHOB           { "echo_b" },
	ECHOS           { "echo_s" },
	CAST			{ "cast__" },
}


enum BCCastKind : char (String asStr)
{
	IDENTITY			{ "nocast"},
    INT_TO_FLOAT		{ "i->f"},	
	INT_TO_DOUBLE		{ "i->d"},
	FLOAT_TO_INT		{ "f->i"},
	FLOAT_TO_DOUBLE		{ "f->d"},
	DOUBLE_TO_INT		{ "d->i"},
	DOUBLE_TO_FLOAT		{ "d->f"},
}


enum BCOpCodeCategory : char (String asStr)
{
	ADD			{ "add" },
	SUB			{ "sub" },
	MUL			{ "mul" },
	DIV			{ "mul" },
	MOV			{ "mov" },
	CONST		{ "const" },
	STOR		{ "store" },
	EQ			{ "equal" },
	NEQ			{ "not equal" },
	LESS		{ "less" },
	LESS_EQ		{ "less equal" },
	GREATER		{ "greater" },
	GREATER_EQ 	{ "greater equal" },
	AND			{ "and" },
	OR			{ "or" },
	JUMP		{ "jump" },
	BRANCH		{ "branch" },
	CALL  		{ "call" },
	RETURN 		{ "return" },
}


enum BCOperandKind : char (String asStr)
{
	INVALID		{ "invalid!" },
	REGISTER 	{ "reg" },
	PLACE 		{ "place" },
	IMM_INT 	{ "imm_i" },
	IMM_FLOAT 	{ "imm_f" },
	IMM_DOUBLE  { "imm_d" },
	IMM_BOOL 	{ "imm_b" },
	IMM_STRING 	{ "imm_s" },
	IMM_NULL 	{ "null" },
	BLOCK 		{ "block" },
	FUNCTION 	{ "fn" },
	MOVE_SIZE	{ "mov_size" },
	CAST_TYPE	{ "cast_type" },
}

struct BCInstruction
{
    union {
        int immInt;
        float immFloat;
        double immDouble;
		bool immBool;
		InternedString immString;
		ushort byteCount;
	    BCCastKind castKind;
		BCCallInfoIdx callInfoIdx;
		BCBlockIdx  blockToJumpTo;
    }
	short 		destOffset;
	short 		leftOffset;
	short 		rightOffset;
    BCOpCode 	opCode;
    BCOperandKind immKind;
}

struct BCFunction
{
	BCFunctionIdx 		idx;
	SymbolIdx 			symbolIdx;
	BCFrameSlotIdx 		layoutStart;
	BCFrameSlotIdx 		layoutEnd;
	BCBlockIdx          blocksStart;
	BCBlockIdx	        blocksEnd;
	short 				frameSize;
}

struct BCFrameSlot
{
	SymbolIdx 		symbolIdx;
	short			sloIdx;
	short 			offset;
	short 			size;
	ValueType 		type;
}

struct BCCallInfo
{
	BCFunctionIdx calleeIdx;
    BCArgIdx argsStart;
	BCArgIdx argsEnd;
	short returnDestOffset; // caller-frame offset, or NO_OFFSET if discarded
	short returnSize;
}

struct BCCallArg
{
    short callerOffset; // where arg value is in caller frame
	short calleeOffset; // aligned parameter offset in callee frame
	short size;
    ValueType type;
	bool copyBack; // INOUT parameters are copied back before the callee frame is discarded
}

struct BCBlock
{
    BCInstructionIdx instructionsStart;
    BCInstructionIdx instructionsEnd;
    BCInstructionIdx terminatorsStart;
    BCInstructionIdx terminatorsEnd;
}

struct BCProjection
{
	int placeholder;
}


struct BCProgram
{
	BCFunctionIdx 		entryFunctionIdx;
	List{BCFunction}	functions;
	List{BCFrameSlot} 	functionFrameSlots;
	List{BCBlock}       blocks;
	List{BCInstruction} instructions;
	List{BCCallArg} 	callArgs;
	List{BCCallInfo}	callInfos;
}

fn void BCProgram.init(BCProgram* this, Allocator allocator)
{
	this.functions.init(allocator);
	this.functionFrameSlots.init(allocator);
	this.blocks.init(allocator);
	this.instructions.init(allocator);
	this.callArgs.init(allocator);
	this.callInfos.init(allocator);
}

fn void BCProgram.print(BCProgram* this)
{
	log::logn("---------- BYTECODE ----------");
	foreach (&fun : this.functions)
	{
		log::logn("function_%s symbolIdx=%s", fun.idx, fun.symbolIdx);
		log::logn("  frame_slots:");
		for (int slotIdx = fun.layoutStart; slotIdx < fun.layoutEnd; slotIdx++) {
			if (slotIdx >= this.functionFrameSlots.len()) {
				log::logn("    <bad-slot-idx:%s>", slotIdx);
				continue;
			}
			this.print_frame_slot(slotIdx, this.functionFrameSlots[slotIdx]);
		}
		log::logn("  instructions:");
		for (int blockIdx = fun.blocksStart; blockIdx < fun.blocksEnd; blockIdx++){
		    log::logn("  block_%s", blockIdx);
		    this.print_block(blockIdx);
		}
		log::logn("");
	}
	log::logn("------------------------------");
}

fn void BCProgram.print_block(BCProgram* this, BCBlockIdx idx)
{
    BCBlock* block = &this.blocks[idx];
    for (int instIdx = block.instructionsStart; instIdx < block.instructionsEnd; instIdx++) {
        if (instIdx >= this.instructions.len()) {
            log::logn("    <bad-inst-idx:%s>", instIdx);
            continue;
        }
        log::log("    %03d: ", instIdx);
        this.print_instruction(this.instructions[instIdx]);
    }
    for (int termIdx = block.terminatorsStart; termIdx < block.terminatorsEnd; termIdx++) {
        if (termIdx >= this.instructions.len()) {
            log::logn("    <bad-inst-idx:%s>", termIdx);
            continue;
        }
        log::log("    %03d: ", termIdx);
        this.print_instruction(this.instructions[termIdx]);
    }
}


fn void BCProgram.print_frame_slot(BCProgram* this, BCFrameSlotIdx idx, BCFrameSlot slot)
{
	log::log("    [%03d] | ", idx);
	log::log("r%03d |", idx);
	log::logn(" symbolIdx : %03d | type : %06s | offset:%03d | size:%03d", slot.symbolIdx, slot.type, slot.offset, slot.size);
}

fn void BCProgram.print_instruction(BCProgram* this, BCInstruction inst)
{
	log::log("%s", inst.opCode.asStr);
	if (inst.destOffset != NO_OFFSET) {
		log::log(", ");
		this.print_offset(inst.destOffset);
	}
	if (inst.leftOffset != NO_OFFSET) {
		log::log(", ");
		this.print_offset(inst.leftOffset);
	}
	if (inst.rightOffset != NO_OFFSET) {
		log::log(", ");
		this.print_offset(inst.rightOffset);
	}
	if (inst.immKind != BCOperandKind.INVALID) {
		log::log(", ");
		this.print_immediate(inst);
		if(inst.immKind == BCOperandKind.FUNCTION){
			BCCallInfo callInfo = this.callInfos[inst.callInfoIdx];
			log::log("| args: ->[");
			this.print_call_info(callInfo);
			log::log("]");
		}
	}
	log::logn("");
}
fn void BCProgram.print_offset(BCProgram* this, short offset)
{
	log::log("@_%02d", offset);
}

fn void BCProgram.print_immediate(BCProgram* this, BCInstruction inst)
{
	switch (inst.immKind) {
		case BCOperandKind.IMM_INT:		log::log("%s", inst.immInt);
		case BCOperandKind.IMM_FLOAT:	log::log("%s", inst.immFloat);
		case BCOperandKind.IMM_DOUBLE:	log::log("%s", inst.immDouble);
		case BCOperandKind.IMM_BOOL:	log::log("%s", inst.immBool);
		case BCOperandKind.IMM_STRING:	log::log("%s", inst.immString.text());
		case BCOperandKind.FUNCTION:	log::log("function_%s", this.callInfos[inst.callInfoIdx].calleeIdx);
		case BCOperandKind.IMM_NULL:	log::log("null");
		case BCOperandKind.BLOCK:	    log::log("block_%s", inst.blockToJumpTo);
		case BCOperandKind.MOVE_SIZE:	log::log("move %s bytes", inst.byteCount);
		case BCOperandKind.CAST_TYPE:	log::log("| cast: %s", inst.castKind.asStr);
		default:						log::log("<?>");
	}
}

fn void BCProgram.print_call_info(BCProgram* this, BCCallInfo callInfo)
{
	for(short i = callInfo.argsStart; i < callInfo.argsEnd; i++){
		log::log("(", this.callArgs[i].type);
		this.print_offset(this.callArgs[i].callerOffset);
		log::log(" | type: %s)", this.callArgs[i].type);
	}
}

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
	NOP							{ "_________" },
	ADDI	        			{ "add_____i" },
	ADDF	        			{ "add_____f" },
	ADDD	        			{ "add_____d" },
	ADDI_IM						{ "add___i_k" },
	INCREMENT					{ "inc_____1" },
	SUBI	        			{ "sub_____i" },
	SUBF	        			{ "sub_____f" },
	SUBD	        			{ "sub_____d" },
	MULI	        			{ "mul_____i" },
	MULF	        			{ "mul_____f" },
	MULD	        			{ "mul_____d" },
	DIVI	        			{ "div_____i" },
	DIVF	        			{ "div_____f" },
	DIVD	        			{ "div_____d" },
	MOVI	        			{ "mov_____i" },
	MOVF	        			{ "mov_____f" },
	MOVD	        			{ "mov_____d" },
	MOVB	        			{ "mov_____b" },
	MOV_REF	        			{ "mov___ref" },
	LOAD_BORROW					{ "load_borw" },
	LOAD_REF_VALUE				{ "loadref_v" },
	STORE_BORROW				{ "stor_borw" },
	STORE_REF_VALUE				{ "storref_v" },
	LOAD_GLOBAL					{ "load__glb" },
	LOAD_GLOBAL_REF_VALUE		{ "loadglb_v" },
	STORE_GLOBAL				{ "stor__glb" },
	STORE_GLOBAL_REF_VALUE		{ "storglb_v" },
	AND							{ "and_____b" },
	OR							{ "or______b" },
	MOV_BYTES	    			{ "mov_bytes" },
	CONSTI	        			{ "const___i" },
	CONSTF	        			{ "const___f" },
	CONSTD	        			{ "const___d" },
	CONSTB	        			{ "const___b" },
	CONSTS	        			{ "const___s" },
	STORI	        			{ "store___i" },
	STORF	        			{ "store___f" },
	STORD	        			{ "store___d" },
	EQI		        			{ "equal___i" },
	EQF		        			{ "equal___f" },
	EQD		        			{ "equal___d" },
	EQB		        			{ "equal___b" },
	NEQI	        			{ "not_eq__i" },
	NEQF	        			{ "not_eq__f" },
	NEQD	        			{ "not_eq__d" },
	NEQB	        			{ "not_eq__b" },
	LESSI	        			{ "less____i" },
	LESSI_IM	    			{ "less__i_k" },
	LESSF	        			{ "less____f" },
	LESSD	        			{ "less____d" },
	LESS_EQI	    			{ "less_eq_i" },
	LESS_EQF	    			{ "less_eq_f" },
	LESS_EQD	    			{ "less_eq_d" },
	GREATERI        			{ "greater_i" },
	GREATERF        			{ "greater_f" },
	GREATERD        			{ "greater_d" },
	GREATER_EQI     			{ "great_eqi" },
	GREATER_EQF     			{ "great_eqf" },
	GREATER_EQD     			{ "great_eqd" },
	JUMP	        			{ "jump_____" },
	BRANCH_IF_FALSE				{ "br_false_" },
	CALL  	        			{ "call_____" },
	RETURN 	        			{ "return___" },
	ECHOI           			{ "echo____i" },
	ECHOF           			{ "echo____f" },
	ECHOD           			{ "echo____d" },
	ECHOB           			{ "echo____b" },
	ECHOS           			{ "echo____s" },
	ECHO_REF        			{ "echo__ref" },
	CAST						{ "cast_____" },
	ALLOC_GC					{ "alloc__gc" },
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
	TYPE_INFO	{ "type_info" },
}

struct BCInstruction
{
    union {
        int immInt;
        float immFloat;
        double immDouble;
		bool immBool;
		StringIdx immStringIdx;
		TypeInfo typeInfo;
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
	short 			offset;
	short 			size;
	ValueType 		type;
}

struct BCGlobalSlot
{
	SymbolIdx 		symbolIdx;
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
	short callerOffset; // value offset, or base-place offset for a borrow
	short calleeOffset; // aligned parameter offset in callee frame
	short size;
	short projectionOffset;
    ValueType type;
	bool isBorrow;
	bool callerIsBorrow;
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
	BCFunctionIdx 			entryFunctionIdx;
	List{BCFunction}		functions;
	List{BCFrameSlot} 		functionFrameSlots;
	List{BCBlock}       	blocks;
	List{BCInstruction} 	instructions;
	List{BCCallArg} 		callArgs;
	List{BCCallInfo}		callInfos;
	List{String}			strings;	// Indexed by StringIdx
	List{BCGlobalSlot} 		globalSlots;
	List{char}				globalInitialData;
	short					globalMemorySize;
}

fn void BCProgram.init(BCProgram* this, Allocator allocator)
{
	this.functions.init(allocator);
	this.globalSlots.init(allocator);
	this.globalInitialData.init(allocator);
	this.functionFrameSlots.init(allocator);
	this.blocks.init(allocator);
	this.instructions.init(allocator);
	this.callArgs.init(allocator);
	this.callInfos.init(allocator);
	this.strings.init(allocator);
}

fn void BCProgram.print(BCProgram* this)
{
	log::logn("---------- BYTECODE ----------");
	log::logn("global slots:");
	foreach (&slot : this.globalSlots) {
		log::logn("  symbolIdx:%s | offset:%s | size:%s | type:%s", slot.symbolIdx, slot.offset, slot.size, slot.type);
	}
	log::logn("");
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
		case BCOperandKind.IMM_STRING:	log::log("%s", this.strings[inst.immStringIdx]);
		case BCOperandKind.FUNCTION:	log::log("function_%s", this.callInfos[inst.callInfoIdx].calleeIdx);
		case BCOperandKind.IMM_NULL:	log::log("null");
		case BCOperandKind.BLOCK:	    log::log("block_%s", inst.blockToJumpTo);
		case BCOperandKind.MOVE_SIZE:	log::log("move %s bytes", inst.byteCount);
		case BCOperandKind.CAST_TYPE:	log::log("| cast: %s", inst.castKind.asStr);
		case BCOperandKind.TYPE_INFO:
			log::log("| type: %s", inst.typeInfo.type);
			if(inst.typeInfo.type == ValueType.REF || inst.typeInfo.type == ValueType.PTR){
				log::log(" to %s", inst.typeInfo.refToType);
			}
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

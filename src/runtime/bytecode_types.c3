module runtime;
import compiler::analyzer;
import std::collections::list;
import common;
import log;

alias BCFunctionIdx = sz;
alias BCBlockIdx = sz;
alias BCInstructionIdx = sz;
alias BCProjectionIdx = sz;
alias BCFrameSlotIdx = sz;

const NO_OFFSET = -1;


enum BCOpCode : char (String asStr)
{
	ADDI	{ "add_i" },
	ADDF	{ "add_f" },	
	ADDD	{ "add_d" },
	SUBI	{ "sub_i" },
	SUBF	{ "sub_f" },
	SUBD	{ "sub_d" },
	MULI	{ "mul_i" },
	MULF	{ "mul_f" },
	MULD	{ "mul_d" },
	MOVI	{ "mov_i" },
	MOVF	{ "mov_f" },
	MOVD	{ "mov_d" },
	CONSTI	{ "const_i" },
	CONSTF	{ "const_f" },
	CONSTD	{ "const_d" },
	STORI	{ "stor_i" },
	STORF	{ "stor_f" },
	STORD	{ "stor_d" },
	JUMP	{ "jump" },
	BRANCH	{ "branch" },
	RETURN 	{ "return" },
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
	IMM_NULL 	{ "null" },
	BLOCK 		{ "block" },
	FUNCTION 	{ "fn" },
}

struct BCInstruction
{
	short 		destOffset;
	short 		leftOffset;
	short 		rightOffset;
    union {
        int immInt;
        float immFloat;
        double immDouble;
        bool immBool;
    }
    BCOpCode 	opCode;
    BCOperandKind immKind;
}

struct BCFunction
{
	BCFunctionIdx 		idx;
	SymbolIdx 			symbolIdx;
	BCFrameSlotIdx 		layoutStart;
	BCFrameSlotIdx 		layoutEnd;
	BCInstructionIdx	instructionsStart;
	BCInstructionIdx	instructionsEnd;
}

struct BCFrameSlot
{
	SymbolIdx 		symbolIdx;
	short			sloIdx;
	short 			offset;
	short 			size;
	ValueType 		type;
}

struct BCProjection
{
	int placeholder;
}


struct BCProgram
{
	List{BCFunction}	functions;
	List{BCFrameSlot} 	functionFrameSlots;
	List{BCInstruction} instructions;
	DynamicArenaAllocator allocator;
}

fn void BCProgram.init(BCProgram* this)
{
	this.allocator = {};
	this.allocator.init(mem, 1024);
	this.functions.init(&this.allocator);
	this.functionFrameSlots.init(&this.allocator);
	this.instructions.init(&this.allocator);
}

fn void BCProgram.deinit(BCProgram* this)
{
	this.allocator.free();
}

fn void BCProgram.print(BCProgram* this)
{
	log::logn("---------- BYTECODE ----------");
	foreach (&fun : this.functions)
	{
			log::logn("function_%s symbolIdx=%s", fun.idx, fun.symbolIdx);
		log::logn("  frame_slots:");
		for (sz slotIdx = fun.layoutStart; slotIdx < fun.layoutEnd; slotIdx++) {
			if (slotIdx >= this.functionFrameSlots.len()) {
				log::logn("    <bad-slot-idx:%s>", slotIdx);
				continue;
			}
			this.print_frame_slot(slotIdx, this.functionFrameSlots[slotIdx]);
		}
		for (sz instIdx = fun.instructionsStart; instIdx < fun.instructionsEnd; instIdx++) {
			if (instIdx >= this.instructions.len()) {
				log::logn("    <bad-inst-idx:%s>", instIdx);
				continue;
			}
			log::log("    %s: ", instIdx);
			this.print_instruction(this.instructions[instIdx]);
		}
		log::logn("");
	}
	log::logn("------------------------------");
}

fn void BCProgram.print_frame_slot(BCProgram* this, BCFrameSlotIdx idx, BCFrameSlot slot)
{
	log::log("    [%s] ", idx);
	log::log("r%s", idx);
	log::logn(" symbolIdx:%s type:%s offset:%s size:%s", slot.symbolIdx, slot.type, slot.offset, slot.size);
}

fn void BCProgram.print_instruction(BCProgram* this, BCInstruction inst)
{
	log::log("%s ", inst.opCode.asStr);
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
	}
	log::logn("");
}
fn void BCProgram.print_offset(BCProgram* this, short offset)
{
	log::log("offset:%s", offset);
}

fn void BCProgram.print_immediate(BCProgram* this, BCInstruction inst)
{
	switch (inst.immKind) {
		case BCOperandKind.IMM_INT:		log::log("%s", inst.immInt);
		case BCOperandKind.IMM_FLOAT:	log::log("%s", inst.immFloat);
		case BCOperandKind.IMM_DOUBLE:	log::log("%s", inst.immDouble);
		case BCOperandKind.IMM_BOOL:		log::log("%s", inst.immBool);
		case BCOperandKind.IMM_NULL:		log::log("null");
		default:						log::log("<?>");
	}
}

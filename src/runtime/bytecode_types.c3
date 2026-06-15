module runtime;
import compiler::analyzer;
import std::collections::list;
import common;
import log;

alias BCRegisterID = short;
alias BCFunctionIdx = sz;
alias BCBlockIdx = sz;
alias BCInstructionIdx = sz;
alias BCPlaceIdx = sz;
alias BCProjectionIdx = sz;
alias BCTerminatorIdx = sz;
alias BCFrameSlotIdx = sz;

const NO_BC_REG = -1;

enum BCTerminatorOpCode : char (String asStr)
{
	JUMP		{ "jump" },
	BRANCH		{ "branch" },
	RETURN 		{ "return" },
}

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
	RET		{ "ret"},
	MOVI	{ "mov_i" },
	MOVF	{ "mov_f" },
	MOVD	{ "mov_d" },
	CONSTI	{ "const_i" },
	CONSTF	{ "const_f" },
	CONSTD	{ "const_d" },
	STORI	{ "stor_i" },
	STORF	{ "stor_f" },
	STORD	{ "stor_d" },
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
    BCOpCode opCode;
	BCRegisterID dest;
	BCRegisterID left;
	BCRegisterID right;
    BCOperandKind immKind;
    union {
        int immInt;
        float immFloat;
        double immDouble;
        bool immBool;
    }

}

struct BCFunction
{
	BCFunctionIdx 	idx;
	SymbolIdx 		symbol;
	BCBlockIdx 		blocksStart; 
	BCBlockIdx 		blocksEnd; 
	BCFrameSlotIdx 	layoutStart;
	BCFrameSlotIdx 	layoutEnd;
}

struct BCFrameSlot
{
	SymbolIdx 		symbol;
	BCRegisterID 	register;
	short 			offset;
	short 			size;
	ValueType 		type;
}

struct BCBlock
{
	BCBlockIdx 			idx;
	BCInstructionIdx 	instructionsStart;
	BCInstructionIdx 	instructionsEnd;
	BCTerminatorIdx 	terminator;
}

struct BCRegister
{
	ValueType 			type;
	BCRegisterID 		id;
	// uint				flags;
	// Additional runtime stuff maybe
}


struct BCOperand
{
	int placeholder;
}

struct BClace
{
	int placeholder;
}

struct BCProjection
{
	int placeholder;
}

struct BCTerminator
{
	BCTerminatorOpCode opCode;
}


struct BCProgram
{
	List{BCFunction}	functions;
	List{BCFrameSlot} 	functionFrameSlots;
	List{BCBlock}		blocks;
	List{BCInstruction} instructions;
	DynamicArenaAllocator allocator;
}

fn void BCProgram.init(BCProgram* this)
{
	this.allocator = {};
	this.allocator.init(mem, 1024);
	this.functions.init(&this.allocator);
	this.functionFrameSlots.init(&this.allocator);
	this.blocks.init(&this.allocator);
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
			log::logn("function_%s symbol=%s", fun.idx, fun.symbol);
		log::logn("  frame_slots:");
		for (sz slotIdx = fun.layoutStart; slotIdx < fun.layoutEnd; slotIdx++) {
			if (slotIdx >= this.functionFrameSlots.len()) {
				log::logn("    <bad-slot-idx:%s>", slotIdx);
				continue;
			}
			this.print_frame_slot(slotIdx, this.functionFrameSlots[slotIdx]);
		}
		for (sz blockIdx = fun.blocksStart; blockIdx < fun.blocksEnd; blockIdx++) {
			if (blockIdx >= this.blocks.len()) {
				log::logn("  <bad-block-idx:%s>", blockIdx);
				continue;
			}
			this.print_block(this.blocks[blockIdx]);
		}
		log::logn("");
	}
	log::logn("------------------------------");
}

fn void BCProgram.print_frame_slot(BCProgram* this, BCFrameSlotIdx idx, BCFrameSlot slot)
{
	log::log("    [%s] ", idx);
	this.print_register(slot.register);
	log::logn(" symbol=%s type=%s offset=%s size=%s", slot.symbol, slot.type, slot.offset, slot.size);
}

fn void BCProgram.print_block(BCProgram* this, BCBlock block)
{
	log::logn("  block_%s:", block.idx);
	for (sz instIdx = block.instructionsStart; instIdx < block.instructionsEnd; instIdx++) {
		if (instIdx >= this.instructions.len()) {
			log::logn("    <bad-inst-idx:%s>", instIdx);
			continue;
		}
		log::log("    %s: ", instIdx);
		this.print_instruction(this.instructions[instIdx]);
	}
}

fn void BCProgram.print_instruction(BCProgram* this, BCInstruction inst)
{
	log::log("%s ", inst.opCode.asStr);
	this.print_register(inst.dest);
	if (inst.left != NO_BC_REG) {
		log::log(", ");
		this.print_register(inst.left);
	}
	if (inst.right != NO_BC_REG) {
		log::log(", ");
		this.print_register(inst.right);
	}
	if (inst.immKind != BCOperandKind.INVALID) {
		log::log(", ");
		this.print_immediate(inst);
	}
	log::logn("");
}

fn void BCProgram.print_register(BCProgram* this, BCRegisterID reg)
{
	if (reg == NO_BC_REG) {
		log::log("<noreg>");
		return;
	}
	log::log("r%s", reg);
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

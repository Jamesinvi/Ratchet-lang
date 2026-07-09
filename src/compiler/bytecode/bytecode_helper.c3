module compiler::bytecode;
import compiler;
import compiler::mir;
import common;
import runtime;
import log;
import globals;

<* 
 	Should be called before lowering a function.
	Will clear out all local offsets and prefill mirRegToOffset and symbolToOffset to the correct size
	with runtime::NO_OFFSET
*>
fn void BCGenerator.prepare_func_bindings(BCGenerator* this, MirFunction* mirFunc)
{
	// Clear the bindings
	this.mirRegToOffset.clear();
	this.mirRegToType.clear();
	this.symbolToOffset.clear();
	int maxMirReg = compiler::mir::NO_REG;
	// We need to find the instruction with the highest "result" register index
	for(sz i = mirFunc.blocksStart; i<mirFunc.blocksEnd;i++){
		MirBlock* mirBlock = &this.mirInput.blocks[i];
		for(sz j = mirBlock.instructionsStart; j<mirBlock.instructionsEnd;j++){
			MirInstruction* mirInstruction = &this.mirInput.instructions[j];
			if (mirInstruction.result != compiler::mir::NO_REG){
				maxMirReg = max(maxMirReg, mirInstruction.result);
			}
		}	
	}
	// Fill the lists with invalid bytecode registers, they will be bound as soon as they're needed
	common::list_append_fill{short}(&this.mirRegToOffset, runtime::NO_OFFSET, (sz)maxMirReg +1 );
	common::list_append_fill{CompTypeInfo}(&this.mirRegToType,   {}, (sz)maxMirReg +1);
	common::list_append_fill{short}(&this.symbolToOffset, runtime::NO_OFFSET, (sz)this.symbolTable.symbols.len() +1);
}

fn BCFunctionIdx BCGenerator.push_func_get_idx(BCGenerator* this, BCFunction* func){
    BCFunctionIdx index = (BCFunctionIdx)this.bcOutput.functions.len();
	func.idx = index;
    this.bcOutput.functions.push(*func);
    return index;
}

<* 
 	Helper to bind a symbol to an offset. If the binding already exists it will return the already bound offset.
	Else, it will bind the offset to the symbol and will create a BCFrameSlot
	The value will be stored in symbolToOffset and indexed by SymbolIdx.
*>
fn short BCGenerator.bind_symbol_get_offset(BCGenerator* this, SymbolIdx symbolIdx)
{
	short offset = this.symbolToOffset[symbolIdx];
	// If we already have a binding then use it, else we need to create one
	if (offset == runtime::NO_OFFSET) {
		Symbol* sym = &this.symbolTable.symbols[symbolIdx];
		short alignment = (short)compiler::get_type_alignment(sym.type);
		this.localFrameOffset = common::align_offset(this.localFrameOffset, alignment);
		short size = (short)compiler::get_type_size(sym.type);

		offset = this.localFrameOffset;
		this.symbolToOffset[symbolIdx] = offset;
		this.localFrameOffset += size;

		BCFrameSlot slot = {
			.symbolIdx = symbolIdx,
			.offset = offset,
			.size = size,
			.type = sym.type.type,
		};

		this.bcOutput.functionFrameSlots.push(slot);
	}
	return offset;
}

<*
	Recurses all projections to get the offset into the type. NOTE: the passed in type will be modified!
	Make sure it's a local value and not some external reference or it will clobber the data.
*>
fn short BCGenerator.resolve_projection_get_offset(BCGenerator* this, MirProjectionIdx idx, CompTypeInfo* type)
{
	if (idx == mir::NO_PROJECTION){
		return 0;
	}

    MirProjection* proj = &this.mirInput.projections[idx];

    short offset = this.resolve_projection_get_offset(proj.prevProjectionIdx, type);

    // Now type is the type after resolving previous projections.
    CompStructTypeInfo* structInfo = &globals::structTypes[type.structTypeIndex];
	FieldInfo* field = &structInfo.fieldInfos[proj.fieldIdx];
	*type = field.typeInfo;
	return offset + (short)field.offset;
}

<* 
 	Helper to bind a mir register to an offset. If the binding already exists it will return the already bound offset.
	Else, it will bind the offset to the register and will create a BCFrameSlot
	The value will be stored in mirRegToOffset and indexed by MirRegisterID.
*>
fn short BCGenerator.bind_mir_register_get_offset(BCGenerator* this, MirRegisterID mirRegId, CompTypeInfo type)
{
	if (mirRegId == compiler::mir::NO_REG) {
		return runtime::NO_OFFSET;
	}

    short offset = this.mirRegToOffset[mirRegId];
	// If we already have a binding then use it, else we need to create one
    if (offset == runtime::NO_OFFSET) {
		short alignment = (short)compiler::get_type_alignment(type);
		this.localFrameOffset = common::align_offset(this.localFrameOffset, alignment);
        short size = (short)compiler::get_type_size(type);

        offset = this.localFrameOffset;

        this.mirRegToOffset[mirRegId] = offset;
		this.mirRegToType[mirRegId] = type;
        this.localFrameOffset += size;

        BCFrameSlot slot = {
            .symbolIdx = compiler::analyzer::NO_SYMBOL,
            .offset = offset,
            .size = size,
            .type = type.type,
        };

        this.bcOutput.functionFrameSlots.push(slot);
    }

    return offset;
}

<* 
 	Helper to bind a mir operand to an offset. If the operand is an immediate, it will emit a mov
	instruction to store the value in a new BCFrameSlot. Else, it will bind a register to it.
*>
fn short BCGenerator.bind_operand_get_offset(BCGenerator* this, MirOperand operand, CompTypeInfo typeInfo)
{
	short offset;
	if (is_immediate(operand)){
		short alignment = (short)compiler::get_type_alignment(typeInfo);
		this.localFrameOffset = common::align_offset(this.localFrameOffset, alignment);
		short size = (short)compiler::get_type_size(typeInfo);
		offset = this.localFrameOffset;
		this.localFrameOffset += size;
		BCFrameSlot slot = {
			.symbolIdx = compiler::analyzer::NO_SYMBOL,
			.offset = offset,
			.size = size,
			.type = typeInfo.type,
		};
		this.bcOutput.functionFrameSlots.push(slot);
		this.store_value(null, operand, offset);
	}else{
		offset = this.bind_mir_register_get_offset(operand.regId, typeInfo);
	}

    return offset;
}




fn bool is_immediate(MirOperand operand)
{
	return operand.kind == MirOperandKind.IMM_BOOL 
		|| operand.kind == IMM_DOUBLE 
		|| operand.kind == IMM_FLOAT 
		|| operand.kind == IMM_INT;
}

<* 
 	Helper to push an instruction and get the index it was added at. Note it pushes a Copy of the BCInstruction
	so any changes you need to make after calling this will have to be made through the returned index
*>
fn BCInstructionIdx BCGenerator.push_instruction_get_idx(BCGenerator* this, BCInstruction* instruction)
{
	BCInstructionIdx index = (BCInstructionIdx)this.bcOutput.instructions.len();
	this.bcOutput.instructions.push(*instruction);
    return index;
}

<* 
 	Helper to push an instruction and get the index it was added at. Note it pushes a Copy of the BCCallInfo
	so any changes you need to make after calling this will have to be made through the returned index
*>
fn BCCallInfoIdx BCGenerator.push_callinfo_get_idx(BCGenerator* this, BCCallInfo* callInfo)
{
	BCCallInfoIdx index = (BCCallInfoIdx)this.bcOutput.callInfos.len();
	this.bcOutput.callInfos.push(*callInfo);
    return index;
}

<* 
 	Helper to push an instruction and get the index it was added at. Note it pushes a Copy of the BCCallArg
	so any changes you need to make after calling this will have to be made through the returned index
*>
fn BCArgIdx BCGenerator.push_callarg_get_idx(BCGenerator* this, BCCallArg* argument)
{
	BCArgIdx index = (BCArgIdx)this.bcOutput.callArgs.len();
	this.bcOutput.callArgs.push(*argument);
    return index;
}

<* 
 	Helper to push an instruction block get the index it was added at. Note it pushes a Copy of the BCBlock
	so any changes you need to make after calling this will have to be made through the returned index
*>
fn BCBlockIdx BCGenerator.push_block_get_idx(BCGenerator* this, BCBlock* block)
{
	BCBlockIdx index = (BCBlockIdx)this.bcOutput.blocks.len();
	this.bcOutput.blocks.push(*block);
    return index;
}

macro BCFrameSlotIdx BCGenerator.fun_frame_slots_len(BCGenerator* this)
{
	assert(this.bcOutput.functionFrameSlots.len() < int::max);
    return (BCFrameSlotIdx)this.bcOutput.functionFrameSlots.len();
}

macro BCBlockIdx BCGenerator.blocks_len(BCGenerator* this)
{
	assert(this.bcOutput.blocks.len() < int::max);
    return (BCBlockIdx)this.bcOutput.blocks.len();
}

macro BCInstructionIdx BCGenerator.instructions_len(BCGenerator* this)
{
	assert(this.bcOutput.instructions.len() < int::max);
    return (BCInstructionIdx)this.bcOutput.instructions.len();
}

fn CompTypeInfo BCGenerator.get_type_from_operand(BCGenerator* this, MirOperand* operand)
{
	switch (operand.kind)
	{
		case MirOperandKind.REGISTER:			
		{

    		CompTypeInfo type = this.mirRegToType[operand.regId];
			// This ensures we have already bound the operand to a proper type
			assert(type.type != ValueType.NULL || type.refToType != ValueType.NULL);
			return type;
		}			
		case MirOperandKind.IMM_INT:						return {.structTypeIndex = compiler::NOT_STRUCT, .type = ValueType.INT, .refToType = ValueType.NULL};
		case MirOperandKind.IMM_FLOAT:						return {.structTypeIndex = compiler::NOT_STRUCT, .type = ValueType.FLOAT, .refToType = ValueType.NULL};
		case MirOperandKind.IMM_DOUBLE:						return {.structTypeIndex = compiler::NOT_STRUCT, .type = ValueType.DOUBLE, .refToType = ValueType.NULL};
		case MirOperandKind.IMM_BOOL:						return {.structTypeIndex = compiler::NOT_STRUCT, .type = ValueType.BOOL, .refToType = ValueType.NULL};
		case MirOperandKind.IMM_NULL:						return {.structTypeIndex = compiler::NOT_STRUCT, .type = ValueType.NULL, .refToType = ValueType.NULL};
		case MirOperandKind.PLACE:		
		{
			log::logn("Places need to be implemented");
			unreachable();
		}		
		case MirOperandKind.BLOCK:							unreachable();
		case MirOperandKind.FUNCTION:						unreachable();
		case MirOperandKind.INVALID:						unreachable();
	}
}

// ----------------------------------------------------------------------------------------------------------------------------------------
// --------------------- Helpers to switch on type and select typed variant of a specific Opcode, very simple stuff -----------------------
// ----------------------------------------------------------------------------------------------------------------------------------------

<*	
	Helper to select a move op code. byteCount is an out parameter that will contain the number of bytes
	to move. The value will be 0 for built-in values (since instruction encodes the size), and non-zero for structs
*>
fn BCOpCode select_mov_op_code(CompTypeInfo typeInfo, ushort* byteCount)
{
	*byteCount = 0;
	switch (typeInfo.type)
	{
		case ValueType.INT:			return BCOpCode.MOVI;
		case ValueType.FLOAT:		return BCOpCode.MOVF;
		case ValueType.DOUBLE:		return BCOpCode.MOVD;
		case ValueType.BOOL:		return BCOpCode.MOVB;
		case ValueType.STRUCT:		
		{
			*byteCount = (ushort)compiler::get_type_size(typeInfo);
			return BCOpCode.MOV_BYTES;
		}
		default:					log::errlogn("Type not supported by bytecode");
	}
	unreachable();
}


fn BCOpCode select_math_op_code(CompTypeInfo typeInfo, BCOpCodeCategory opCodeCategory)
{
	switch (opCodeCategory)
	{
		case BCOpCodeCategory.ADD: return select_add_op_code(typeInfo, opCodeCategory);
		case BCOpCodeCategory.SUB: return select_sub_op_code(typeInfo, opCodeCategory);
		case BCOpCodeCategory.MUL: return select_mul_op_code(typeInfo, opCodeCategory);
		case BCOpCodeCategory.DIV: return select_div_op_code(typeInfo, opCodeCategory);
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
	unreachable();
}

fn BCOpCode select_cmp_op_code(CompTypeInfo typeInfo, BCOpCodeCategory opCodeCategory)
{
	switch (opCodeCategory)
	{
		case BCOpCodeCategory.EQ:  		return select_eq_op_code(typeInfo, opCodeCategory);
		case BCOpCodeCategory.NEQ: 		return select_neq_op_code(typeInfo, opCodeCategory);
		case BCOpCodeCategory.LESS: 	return select_less_op_code(typeInfo, opCodeCategory);
		case BCOpCodeCategory.GREATER: 	return select_grter_op_code(typeInfo, opCodeCategory);
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
	unreachable();
}


fn BCOpCode select_add_op_code(CompTypeInfo typeInfo, BCOpCodeCategory opCodeCategory)
{
	switch(typeInfo.type)
	{
		case ValueType.INT: 		return BCOpCode.ADDI;
		case ValueType.FLOAT: 		return BCOpCode.ADDF;
		case ValueType.DOUBLE: 		return BCOpCode.ADDD;
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
	unreachable();
}

fn BCOpCode select_eq_op_code(CompTypeInfo typeInfo, BCOpCodeCategory opCodeCategory)
{
	switch(typeInfo.type)
	{
		case ValueType.INT: 		return BCOpCode.EQI;
		case ValueType.FLOAT: 		return BCOpCode.EQF;
		case ValueType.DOUBLE: 		return BCOpCode.EQD;
		case ValueType.BOOL: 		return BCOpCode.EQB;
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
	unreachable();
}


fn BCOpCode select_neq_op_code(CompTypeInfo typeInfo, BCOpCodeCategory opCodeCategory)
{
	switch(typeInfo.type)
	{
		case ValueType.INT: 		return BCOpCode.NEQI;
		case ValueType.FLOAT: 		return BCOpCode.NEQF;
		case ValueType.DOUBLE: 		return BCOpCode.NEQD;
		case ValueType.BOOL: 		return BCOpCode.NEQB;
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
	unreachable();
}

fn BCOpCode select_less_op_code(CompTypeInfo typeInfo, BCOpCodeCategory opCodeCategory)
{
	switch(typeInfo.type)
	{
		case ValueType.INT: 		return BCOpCode.LESSI;
		case ValueType.FLOAT: 		return BCOpCode.LESSF;
		case ValueType.DOUBLE: 		return BCOpCode.LESSD;
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
	unreachable();
}

fn BCOpCode select_grter_op_code(CompTypeInfo typeInfo, BCOpCodeCategory opCodeCategory)
{
	switch(typeInfo.type)
	{
		case ValueType.INT: 		return BCOpCode.GREATERI;
		case ValueType.FLOAT: 		return BCOpCode.GREATERF;
		case ValueType.DOUBLE: 		return BCOpCode.GREATERD;
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
	unreachable();
}



fn BCOpCode select_sub_op_code(CompTypeInfo typeInfo, BCOpCodeCategory opCodeCategory)
{
	switch(typeInfo.type)
	{
		case ValueType.INT: 		return BCOpCode.SUBI;
		case ValueType.FLOAT: 		return BCOpCode.SUBF;
		case ValueType.DOUBLE: 		return BCOpCode.SUBD;
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
	unreachable();
}

fn BCOpCode select_mul_op_code(CompTypeInfo typeInfo, BCOpCodeCategory opCodeCategory)
{
	switch(typeInfo.type)
	{
		case ValueType.INT: 		return BCOpCode.MULI;
		case ValueType.FLOAT: 		return BCOpCode.MULF;
		case ValueType.DOUBLE: 		return BCOpCode.MULD;
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
	unreachable();
}

fn BCOpCode select_div_op_code(CompTypeInfo typeInfo, BCOpCodeCategory opCodeCategory)
{
	switch(typeInfo.type)
	{
		case ValueType.INT: 		return BCOpCode.DIVI;
		case ValueType.FLOAT: 		return BCOpCode.DIVF;
		case ValueType.DOUBLE: 		return BCOpCode.DIVD;
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
	unreachable();
}

fn BCOpCode select_echo_op_code(CompTypeInfo typeInfo)
{
    switch(typeInfo.type)
    {
        case ValueType.INT: 		return BCOpCode.ECHOI;
        case ValueType.FLOAT: 		return BCOpCode.ECHOF;
        case ValueType.DOUBLE: 		return BCOpCode.ECHOD;
        case ValueType.BOOL: 		return BCOpCode.ECHOB;
        default:					log::errlogn("Unsupported %s operation", typeInfo.type);
    }
	unreachable();
}
module compiler::bytecode;
import compiler;
import compiler::mir;
import common;
import runtime;
import log;


fn void BCGenerator.prepare_func_bindings(BCGenerator* this, MirFunction* mirFunc)
{
	// Clear the bindings
	this.mirRegToOffset.clear();
	this.symbolToOffset.clear();
	int maxMirReg = compiler::mir::NO_REG;
	// We need to firnd the instruction iwth the highest "result" register index
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
	common::list_fill{short}(&this.mirRegToOffset, runtime::NO_OFFSET, (sz)maxMirReg +1 );
	common::list_fill{short}(&this.symbolToOffset, runtime::NO_OFFSET, (sz)this.symbolTable.symbols.len() +1);
}

fn BCFunctionIdx BCGenerator.push_func_get_idx(BCGenerator* this, BCFunction* func){
    BCFunctionIdx index = this.bcOutput.functions.len();
	func.idx = index;
    this.bcOutput.functions.push(*func);
    return index;
}


fn short BCGenerator.bind_symbol_get_offset(BCGenerator* this, SymbolIdx symbolIdx)
{
	short offset = this.symbolToOffset[symbolIdx];
	// If we already have a binding then use it, else we need to create one
	if (offset == runtime::NO_OFFSET) {
		Symbol* sym = &this.symbolTable.symbols[symbolIdx];
		short alignment = (short)compiler::get_type_alignment(sym.type);
		this.localFrameOffset = align_offset(this.localFrameOffset, alignment);
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


fn short BCGenerator.bind_mir_register_get_offset(BCGenerator* this, MirRegisterID mirRegId, CompTypeInfo type)
{
	if (mirRegId == compiler::mir::NO_REG) {
		return runtime::NO_OFFSET;
	}

    short offset = this.mirRegToOffset[mirRegId];
	// If we already have a binding then use it, else we need to create one
    if (offset == runtime::NO_OFFSET) {
		short alignment = (short)compiler::get_type_alignment(type);
		this.localFrameOffset = align_offset(this.localFrameOffset, alignment);
        short size = (short)compiler::get_type_size(type);

        offset = this.localFrameOffset;

        this.mirRegToOffset[mirRegId] = offset;
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



fn short align_offset(short offset, short alignment)
{
	short remainder = offset % alignment;
	if (remainder == 0) {
		return offset;
	}
	return offset + (alignment - remainder);
}


fn BCOpCode select_mov_op_code(CompTypeInfo typeInfo)
{
	switch (typeInfo.type)
	{
		case ValueType.INT:			return BCOpCode.MOVI;
		case ValueType.FLOAT:		return BCOpCode.MOVF;
		case ValueType.DOUBLE:		return BCOpCode.MOVD;
		default:					log::errlogn("Not suported type by bytecode");
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
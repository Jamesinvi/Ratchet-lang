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
	if (remainder == 0) return offset;
	return offset + (alignment - remainder);
}

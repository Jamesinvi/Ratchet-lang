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
		offset = this.localFrameOffset;
		this.symbolToOffset[symbolIdx] = offset;
		Symbol* sym = &this.symbolTable.symbols[symbolIdx];
		short size = (short)compiler::get_type_size(sym.type);
		BCFrameSlot slot = {
			.symbolIdx = symbolIdx,
			.offset = offset,
			.size = size,
			.type = sym.type.type,
		};

		this.localFrameOffset += size;
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
        offset = this.localFrameOffset;
        this.mirRegToOffset[mirRegId] = offset;

        short size = (short)compiler::get_type_size(type);

        BCFrameSlot slot = {
            .symbolIdx = compiler::analyzer::NO_SYMBOL,
            .offset = offset,
            .size = size,
            .type = type.type,
        };

        this.localFrameOffset += size;
        this.bcOutput.functionFrameSlots.push(slot);
    }

    return offset;
}

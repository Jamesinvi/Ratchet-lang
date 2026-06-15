module compiler::bytecode;
import compiler;
import compiler::mir;
import common;
import runtime;
import log;


fn void BCGenerator.prepare_func_bindings(BCGenerator* this, MirFunction* mirFunc)
{
	// Clear the bindings
	this.mirRegToRegister.clear();
	this.symbolToRegister.clear();
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
	common::list_fill{short}(&this.mirRegToRegister, runtime::NO_BC_REG, (sz)maxMirReg +1 );
	common::list_fill{short}(&this.symbolToRegister, runtime::NO_BC_REG, (sz)this.symbolTable.symbols.len() +1);
}

fn BCFunctionIdx BCGenerator.push_func_get_idx(BCGenerator* this, BCFunction* func){
    BCFunctionIdx index = this.bcOutput.functions.len();
	func.idx = index;
    this.bcOutput.functions.push(*func);
    return index;
}

fn BCBlockIdx BCGenerator.push_block_get_idx(BCGenerator* this, BCBlock* block){
    BCBlockIdx index = this.bcOutput.blocks.len();
	block.idx = index;
    this.bcOutput.blocks.push(*block);
    return index;
}

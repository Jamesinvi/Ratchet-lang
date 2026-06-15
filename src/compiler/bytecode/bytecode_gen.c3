module compiler::bytecode;
import compiler::analyzer;
import common::stack;
import globals;
import compiler;
import runtime;
import log;
import std::collections::list;


struct BCGenerator
{
	ProgramAst* 		inputAst;
	SymbolTable* 		symbolTable;
	MirProgram* 		mirInput;
	BCProgram*			bcOutput;
	BCRegisterID 		nextFreeRegister;
	List{BCRegisterID}	mirRegToRegister; // Indexed by MirRegisterID
	List{BCRegisterID}	symbolToRegister; // Indexed by SymbolIdx
	int 				currentOffset;
}

fn void BCGenerator.init(BCGenerator* this, CompilationContext* ctx)
{
	this.mirInput = &ctx.mirGen.output;
	this.inputAst = &ctx.parser.outputAst;
	this.symbolTable = ctx.mirGen.symbolTable;
	this.bcOutput = &ctx.compiledProgram;
	this.bcOutput.init();
	this.mirRegToRegister.init(mem);
	this.symbolToRegister.init(mem);
}

fn void BCGenerator.deinit(BCGenerator* this)
{
	if (this.bcOutput != null) {
		this.bcOutput.deinit();
	}
}

fn void BCGenerator.run(BCGenerator* this)
{
	foreach(&func : this.mirInput.functions){
		this.currentOffset = 0;
		this.prepare_func_bindings(func);
		BCFunction functionResult = {};
		BCFunctionIdx funcIdx = this.push_func_get_idx(&functionResult);
		this.lower_fun(func, funcIdx);
	}
	this.bcOutput.print();
}
	
fn void BCGenerator.lower_fun(BCGenerator* this, MirFunction* funcInput, BCFunctionIdx funcOutputIdx)
{
	BCFunction* funcOutput = &this.bcOutput.functions[funcOutputIdx];
	funcOutput.blocksStart = this.bcOutput.blocks.len();
	funcOutput.layoutStart = this.bcOutput.functionFrameSlots.len();
	for(sz i = funcInput.blocksStart; i<funcInput.blocksEnd;i++){
		BCBlock block = {};
		BCBlockIdx blockIdx = this.push_block_get_idx(&block);
		this.lower_block(&this.mirInput.blocks[i], funcOutputIdx, blockIdx);
	}
	funcOutput.blocksEnd = this.bcOutput.blocks.len();
	funcOutput.layoutEnd = this.bcOutput.functionFrameSlots.len();
}

fn void BCGenerator.lower_block(BCGenerator* this, MirBlock* mirBlock, BCFunctionIdx currentFuncidx, BCBlockIdx currentBlockIdx)
{
	BCBlock* currentBlock = &this.bcOutput.blocks[currentBlockIdx];
	currentBlock.instructionsStart = this.bcOutput.instructions.len();
	for(sz i = mirBlock.instructionsStart; i<mirBlock.instructionsEnd;i++){
		MirInstruction* mirInstruction = &this.mirInput.instructions[i];
		switch (mirInstruction.opCode){
			case MirOpCode.ADD:
			{
				BCRegisterID resultReg = this.nextFreeRegister++;
				MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand right = this.mirInput.operands[mirInstruction.operandsStart + 1];
				BCRegisterID leftRegister = this.mirRegToRegister[left.regId];
				BCRegisterID rightRegister = this.mirRegToRegister[right.regId];
				this.mirRegToRegister[mirInstruction.result] = resultReg;
				BCInstruction instruction = {
					.opCode = BCOpCode.ADDI,
					.dest = resultReg,
					.left = leftRegister,
					.right = rightRegister,
				};
				this.bcOutput.instructions.push(instruction);
			}
			case MirOpCode.STORE:
			{
				MirOperand dest = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand val = this.mirInput.operands[mirInstruction.operandsStart + 1];
				MirPlace place = this.mirInput.places[dest.placeIdx];
				SymbolIdx symbol = place.baseSymbolIdx;
				// Map the symbol to the registers in bytecode. (Binding)
				BCRegisterID destRegister = this.symbolToRegister[symbol];
				// If we already have a binding then use it, else we need to create one
				if (destRegister == runtime::NO_BC_REG) {
					destRegister = this.nextFreeRegister++;
					this.symbolToRegister[symbol] = destRegister;
					BCFrameSlot slot = {
						.symbol = symbol,
						.register = destRegister,
						.offset = (short)this.currentOffset,
						.size = (short)compiler::get_type_size(mirInstruction.type),
						.type = mirInstruction.type.type,
					};
					this.currentOffset += slot.size;
					this.bcOutput.functionFrameSlots.push(slot);
				}
				this.store_value(destRegister, val);
			}
			case MirOpCode.LOAD:
			{
				BCRegisterID destRegister = this.nextFreeRegister++;
				MirOperand source = this.mirInput.operands[mirInstruction.operandsStart];
				MirPlace place = this.mirInput.places[source.placeIdx];
				SymbolIdx symbol = place.baseSymbolIdx;
				BCRegisterID sourceRegister = this.symbolToRegister[symbol];
				this.mirRegToRegister[mirInstruction.result] = destRegister;
				BCInstruction instruction = {
					.opCode = BCOpCode.MOVI,
					.dest = destRegister,
					.left = sourceRegister,
					.right = runtime::NO_BC_REG,
				};
				this.bcOutput.instructions.push(instruction);
			}
			default:
				log::errlogn("Not suported by compiler");
		}
	}
	currentBlock.instructionsEnd = this.bcOutput.instructions.len();
	this.lower_terminator(currentBlock.terminator);
}


fn void BCGenerator.store_value(BCGenerator* this, BCRegisterID destRegister, MirOperand val)
{
	switch (val.kind) {
		case MirOperandKind.REGISTER:
		{
			BCRegisterID srcRegister = this.mirRegToRegister[val.regId];
			BCInstruction instruction = {
				.opCode = BCOpCode.MOVI,
				.dest = destRegister,
				.left = srcRegister,
				.right = runtime::NO_BC_REG,
			};
			this.bcOutput.instructions.push(instruction);
		}

		case MirOperandKind.IMM_INT:
		{
			BCInstruction instruction = {
				.opCode = BCOpCode.CONSTI,
				.dest = destRegister,
				.left = runtime::NO_BC_REG,
				.right = runtime::NO_BC_REG,
				.immKind = BCOperandKind.IMM_INT,
				.immInt = val.immInt,
			};
			this.bcOutput.instructions.push(instruction);
		}
			default:
				log::errlogn("Not suported by compiler");
	}
}


fn void BCGenerator.lower_terminator(BCGenerator* this, MirTerminatorIdx terminatorIdx)
{
	switch(this.mirInput.terminators[terminatorIdx].opCode)
	{
		case MirTerminatorOp.RETURN:
			BCInstruction instruction = {
				.opCode = BCOpCode.RET,
				.dest = runtime::NO_BC_REG,
				.left = runtime::NO_BC_REG,
				.right = runtime::NO_BC_REG,
			};
			this.bcOutput.instructions.push(instruction);
		default:
			log::errlogn("Not suported by compiler");
	}
}

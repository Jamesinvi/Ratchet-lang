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
	List{short}			symbolToOffset; 	// Indexed by SymbolIdx
	List{short}			mirRegToOffset;	  	// Indexed by MirRegisterID
	int 				currentFrameOffset;
	short 				localFrameOffset;
}

fn void BCGenerator.init(BCGenerator* this, CompilationContext* ctx)
{
	this.mirInput = &ctx.mirGen.output;
	this.inputAst = &ctx.parser.outputAst;
	this.symbolTable = ctx.mirGen.symbolTable;
	this.bcOutput = &ctx.compiledProgram;
	this.bcOutput.init();
	this.symbolToOffset.init(mem);
	this.mirRegToOffset.init(mem);
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
		this.currentFrameOffset = 0;
		this.localFrameOffset = 0;
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
	funcOutput.layoutStart = this.bcOutput.functionFrameSlots.len();
	funcOutput.instructionsStart = this.bcOutput.instructions.len();
	for(sz i = funcInput.blocksStart; i<funcInput.blocksEnd;i++){
		this.lower_block(&this.mirInput.blocks[i], funcOutputIdx);
		this.lower_terminator(this.mirInput.blocks[i].terminator);
	}
	funcOutput.layoutEnd = this.bcOutput.functionFrameSlots.len();
	funcOutput.instructionsEnd = this.bcOutput.instructions.len();
}


fn void BCGenerator.lower_block(BCGenerator* this, MirBlock* mirBlock, BCFunctionIdx currentFuncidx)
{
	for(sz i = mirBlock.instructionsStart; i<mirBlock.instructionsEnd;i++){
		MirInstruction* mirInstruction = &this.mirInput.instructions[i];
		switch (mirInstruction.opCode){
			case MirOpCode.ADD:
			{
				MirRegisterID mirResult = mirInstruction.result;
				MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand right = this.mirInput.operands[mirInstruction.operandsStart + 1];
				short leftOffset = this.bind_operand_get_offset(left, mirInstruction.type);
				short rightOffset = this.bind_operand_get_offset(right, mirInstruction.type);
				short destOffset = this.bind_mir_register_get_offset(mirResult, mirInstruction.type);
				this.lower_math_op(BCOpCodeCategory.ADD, destOffset, leftOffset, rightOffset, mirInstruction.type);
			}
			case MirOpCode.SUB:
			{
				MirRegisterID mirResult = mirInstruction.result;
				MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand right = this.mirInput.operands[mirInstruction.operandsStart + 1];
				short leftOffset = this.bind_operand_get_offset(left, mirInstruction.type);
				short rightOffset = this.bind_operand_get_offset(right, mirInstruction.type);
				short destOffset = this.bind_mir_register_get_offset(mirResult, mirInstruction.type);
				this.lower_math_op(BCOpCodeCategory.SUB, destOffset, leftOffset, rightOffset, mirInstruction.type);
			}
			case MirOpCode.MUL:
			{
				MirRegisterID mirResult = mirInstruction.result;
				MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand right = this.mirInput.operands[mirInstruction.operandsStart + 1];
				short leftOffset = this.bind_operand_get_offset(left, mirInstruction.type);
				short rightOffset = this.bind_operand_get_offset(right, mirInstruction.type);
				short destOffset = this.bind_mir_register_get_offset(mirResult, mirInstruction.type);
				this.lower_math_op(BCOpCodeCategory.MUL, destOffset, leftOffset, rightOffset, mirInstruction.type);
			}
			case MirOpCode.DIV:
			{
				MirRegisterID mirResult = mirInstruction.result;
				MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand right = this.mirInput.operands[mirInstruction.operandsStart + 1];
				short leftOffset = this.bind_operand_get_offset(left, mirInstruction.type);
				short rightOffset = this.bind_operand_get_offset(right, mirInstruction.type);
				short destOffset = this.bind_mir_register_get_offset(mirResult, mirInstruction.type);
				this.lower_math_op(BCOpCodeCategory.DIV, destOffset, leftOffset, rightOffset, mirInstruction.type);
			}
			case MirOpCode.STORE:
			{
				MirOperand dest = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand source = this.mirInput.operands[mirInstruction.operandsStart + 1];
				MirPlace place = this.mirInput.places[dest.placeIdx];
				SymbolIdx symbol = place.baseSymbolIdx;
				short destOffset = this.bind_symbol_get_offset(symbol);
				this.store_value(mirInstruction, source, destOffset);
			}
			case MirOpCode.LOAD:
			{
				MirRegisterID dest = mirInstruction.result;
				MirOperand source = this.mirInput.operands[mirInstruction.operandsStart];
				MirPlace place = this.mirInput.places[source.placeIdx];
				SymbolIdx symbol = place.baseSymbolIdx;
				short srcOffset = this.bind_symbol_get_offset(symbol);
				short destOffset = this.bind_mir_register_get_offset(dest, mirInstruction.type);
				this.load_value(mirInstruction.type, srcOffset, destOffset);
			}
			default:
			{
				log::errlogn("Not suported store by compiler");
			}
		}
	}
}

fn void BCGenerator.store_value(BCGenerator* this, MirInstruction* mirInstruction, MirOperand val, short destOffset)
{
	BCInstruction instruction = {};
	switch (val.kind) {
		case MirOperandKind.REGISTER:
		{
			short srcOffset = this.mirRegToOffset[val.regId];
			instruction.destOffset = destOffset;
			instruction.leftOffset = srcOffset;
			instruction.rightOffset = runtime::NO_OFFSET;
			instruction.opCode = select_mov_op_code(mirInstruction.type);
			instruction.immKind = BCOperandKind.INVALID;
		}
		case MirOperandKind.IMM_INT:
		{
			instruction.destOffset = destOffset;
			instruction.leftOffset = runtime::NO_OFFSET;
			instruction.rightOffset = runtime::NO_OFFSET;
			instruction.immInt = val.immInt;
			instruction.opCode = BCOpCode.CONSTI;
			instruction.immKind = BCOperandKind.IMM_INT;
		}
		case MirOperandKind.IMM_DOUBLE:
		{
			instruction.destOffset = destOffset;
			instruction.leftOffset = runtime::NO_OFFSET;
			instruction.rightOffset = runtime::NO_OFFSET;
			instruction.immDouble = val.immDouble;
			instruction.opCode = BCOpCode.CONSTD;
			instruction.immKind = BCOperandKind.IMM_DOUBLE;
		}
		default:
		{
			log::errlogn("Not suported store by compiler");
			unreachable();
		}
	}
	this.bcOutput.instructions.push(instruction);

}

fn void BCGenerator.load_value(BCGenerator* this, CompTypeInfo typeInfo, short srcOffset, short destOffset)
{
	BCInstruction instruction = {
		.destOffset = destOffset,
		.leftOffset = srcOffset,
		.rightOffset = runtime::NO_OFFSET,
		.immInt = runtime::NO_OFFSET,
		.opCode = select_mov_op_code(typeInfo),
		.immKind = BCOperandKind.INVALID,
	};
	this.bcOutput.instructions.push(instruction);
}


fn void BCGenerator.lower_math_op(BCGenerator* this, BCOpCodeCategory opCodeCategory, short destOffset, short leftOffset, short rightOffset, CompTypeInfo typeInfo)
{	
	BCOpCode finalOpCode = select_math_op_code(typeInfo, opCodeCategory);
	BCInstruction instruction = {
		.destOffset = destOffset,
		.leftOffset = leftOffset,
		.rightOffset = rightOffset,
		.immInt = runtime::NO_OFFSET,
		.opCode = finalOpCode,
		.immKind = BCOperandKind.INVALID,
	};
	this.bcOutput.instructions.push(instruction);


}
fn void BCGenerator.lower_terminator(BCGenerator* this, MirTerminatorIdx terminatorIdx)
{
	switch(this.mirInput.terminators[terminatorIdx].opCode)
	{
		case MirTerminatorOp.RETURN:
		{
			BCInstruction instruction = {
				.destOffset = runtime::NO_OFFSET,
				.leftOffset = runtime::NO_OFFSET,
				.rightOffset = runtime::NO_OFFSET,
				.opCode = BCOpCode.RETURN,
				.immKind = BCOperandKind.INVALID,
			};
			this.bcOutput.instructions.push(instruction);
		}
		default:
		{
			log::errlogn("Not suported store by compiler");
			unreachable();
		}
	}
}

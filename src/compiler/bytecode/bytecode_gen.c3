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
				assert(left.kind == MirOperandKind.REGISTER);
				assert(right.kind == MirOperandKind.REGISTER);
				short leftOffset = this.mirRegToOffset[left.regId];
				short rightOffset = this.mirRegToOffset[right.regId];
				short destOffset = this.bind_mir_register_get_offset(mirResult, mirInstruction.type);
				this.lower_math_op(BCOpCodeCategory.ADD, destOffset, leftOffset, rightOffset, mirInstruction.type);
			}
			case MirOpCode.SUB:
			{
				MirRegisterID mirResult = mirInstruction.result;
				MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand right = this.mirInput.operands[mirInstruction.operandsStart + 1];
				assert(left.kind == MirOperandKind.REGISTER);
				assert(right.kind == MirOperandKind.REGISTER);
				short leftOffset = this.mirRegToOffset[left.regId];
				short rightOffset = this.mirRegToOffset[right.regId];
				short destOffset = this.bind_mir_register_get_offset(mirResult, mirInstruction.type);
				this.lower_math_op(BCOpCodeCategory.SUB, destOffset, leftOffset, rightOffset, mirInstruction.type);
			}
			case MirOpCode.MUL:
			{
				MirRegisterID mirResult = mirInstruction.result;
				MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand right = this.mirInput.operands[mirInstruction.operandsStart + 1];
				assert(left.kind == MirOperandKind.REGISTER);
				assert(right.kind == MirOperandKind.REGISTER);
				short leftOffset = this.mirRegToOffset[left.regId];
				short rightOffset = this.mirRegToOffset[right.regId];
				short destOffset = this.bind_mir_register_get_offset(mirResult, mirInstruction.type);
				this.lower_math_op(BCOpCodeCategory.MUL, destOffset, leftOffset, rightOffset, mirInstruction.type);
			}
			case MirOpCode.DIV:
			{
				MirRegisterID mirResult = mirInstruction.result;
				MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand right = this.mirInput.operands[mirInstruction.operandsStart + 1];
				assert(left.kind == MirOperandKind.REGISTER);
				assert(right.kind == MirOperandKind.REGISTER);
				short leftOffset = this.mirRegToOffset[left.regId];
				short rightOffset = this.mirRegToOffset[right.regId];
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
				this.store_value(source, destOffset);
			}
			case MirOpCode.LOAD:
			{
				MirRegisterID mirDest = mirInstruction.result;
				MirOperand mirSource = this.mirInput.operands[mirInstruction.operandsStart];
				MirPlace place = this.mirInput.places[mirSource.placeIdx];
				SymbolIdx symbol = place.baseSymbolIdx;
				short srcOffset = this.bind_symbol_get_offset(symbol);
				short destOffset = this.bind_mir_register_get_offset(mirDest, mirInstruction.type);
				BCInstruction instruction = {
					.destOffset = destOffset,
					.leftOffset = srcOffset,
					.rightOffset = runtime::NO_OFFSET,
					.immInt = runtime::NO_OFFSET,
					.opCode = BCOpCode.MOVI,
					.immKind = BCOperandKind.INVALID,
				};
				this.bcOutput.instructions.push(instruction);
			}
			default:
				log::errlogn("Not suported by compiler");
		}
	}
}

fn void BCGenerator.lower_math_op(BCGenerator* this, BCOpCodeCategory opCodeCategory, short destOffset, short leftOffset, short rightOffset, CompTypeInfo typeInfo)
{	
	BCOpCode finalOpCode;
	switch(opCodeCategory)
	{
		case BCOpCodeCategory.ADD:
		{

			switch(typeInfo.type)
			{
				case ValueType.INT: 		finalOpCode = BCOpCode.ADDI;
				case ValueType.FLOAT: 		finalOpCode = BCOpCode.ADDF;
				case ValueType.DOUBLE: 		finalOpCode = BCOpCode.ADDD;
				default:					log::errlogn("Unsupported %s operation", opCodeCategory);
			}
		}
		case BCOpCodeCategory.SUB:
		{

			switch(typeInfo.type)
			{
				case ValueType.INT: 		finalOpCode = BCOpCode.SUBI;
				case ValueType.FLOAT: 		finalOpCode = BCOpCode.SUBF;
				case ValueType.DOUBLE: 		finalOpCode = BCOpCode.SUBD;
				default:					log::errlogn("Unsupported %s operation", opCodeCategory);
			}
		}
		case BCOpCodeCategory.MUL:
		{

			switch(typeInfo.type)
			{
				case ValueType.INT: 		finalOpCode = BCOpCode.MULI;
				case ValueType.FLOAT: 		finalOpCode = BCOpCode.MULF;
				case ValueType.DOUBLE: 		finalOpCode = BCOpCode.MULD;
				default:					log::errlogn("Unsupported %s operation", opCodeCategory);
			}
		}
		case BCOpCodeCategory.DIV:
		{

			switch(typeInfo.type)
			{
				case ValueType.INT: 		finalOpCode = BCOpCode.DIVI;
				case ValueType.FLOAT: 		finalOpCode = BCOpCode.DIVF;
				case ValueType.DOUBLE: 		finalOpCode = BCOpCode.DIVD;
				default:					log::errlogn("Unsupported %s operation", opCodeCategory);
			}
		}
		default:					log::errlogn("Unsupported %s operation", opCodeCategory);
	}
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

fn void BCGenerator.store_value(BCGenerator* this, MirOperand val, short destOffset)
{
	switch (val.kind) {
		case MirOperandKind.REGISTER:
		{
			short srcOffset = this.mirRegToOffset[val.regId];
			BCInstruction instruction = {
				.destOffset = destOffset,
				.leftOffset = srcOffset,
				.rightOffset = runtime::NO_OFFSET,
				.opCode = BCOpCode.MOVI,
				.immKind = BCOperandKind.INVALID,
			};
			this.bcOutput.instructions.push(instruction);
		}

		case MirOperandKind.IMM_INT:
		{
			BCInstruction instruction = {
				.destOffset = destOffset,
				.leftOffset = runtime::NO_OFFSET,
				.rightOffset = runtime::NO_OFFSET,
				.immInt = val.immInt,
				.opCode = BCOpCode.CONSTI,
				.immKind = BCOperandKind.IMM_INT,
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
			log::errlogn("Not suported by compiler");
	}
}

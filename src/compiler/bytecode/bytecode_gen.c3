module compiler::bytecode;
import compiler::analyzer;
import common::stack;
import globals;
import compiler;
import runtime;
import log;
import debug;
import std::collections::list;


struct BCGenerator
{
	ProgramAst* 		inputAst;
	SymbolTable* 		symbolTable;
	MirProgram* 		mirInput;
	BCProgram*			bcOutput;
	List{short}			symbolToOffset; 	// Indexed by SymbolIdx
	List{short}			mirRegToOffset;	  	// Indexed by MirRegisterID
	List{CompTypeInfo}  mirRegToType;		// Indexed by MirRegisterID
	List{BCFunctionIdx} declToBcFunction;	// Indexed by DeclIdx (source)
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
	this.mirRegToType.init(mem);
	this.declToBcFunction.init(mem);
}

fn void BCGenerator.deinit(BCGenerator* this)
{
	if (this.bcOutput != null) {
		this.bcOutput.deinit();
	}
	this.symbolToOffset.free();
	this.mirRegToOffset.free();
	this.mirRegToType.free();
	this.declToBcFunction.free();
}

fn void BCGenerator.run(BCGenerator* this)
{
	common::list_append_fill{BCFunctionIdx}(&this.declToBcFunction, -1, this.inputAst.declarations.len());
	// First pass: add all functions to the declToBcFuntion list
	foreach(&func : this.mirInput.functions){
		BCFunction functionResult = {};
		BCFunctionIdx funcIdx = this.push_func_get_idx(&functionResult);
		this.declToBcFunction[func.sourceDeclIdx] = funcIdx;
	}
	// Second pass: actually lower the function instructions
	foreach(&func : this.mirInput.functions){
		BCFunctionIdx funcIdx = this.declToBcFunction[func.sourceDeclIdx];
		this.currentFrameOffset = 0;
		this.localFrameOffset = 0;
		this.prepare_func_bindings(func);
		this.lower_fun(func, funcIdx);
	}
	optimize(this.bcOutput);

}
	
fn void BCGenerator.lower_fun(BCGenerator* this, MirFunction* funcInput, BCFunctionIdx funcOutputIdx)
{
	BCFunction* funcOutput = &this.bcOutput.functions[funcOutputIdx];
	funcOutput.layoutStart = this.fun_frame_slots_len();
	funcOutput.blocksStart = this.blocks_len();
	for(int i = funcInput.blocksStart; i<funcInput.blocksEnd;i++){
		BCBlockIdx loweredBlockIdx = this.lower_block(&this.mirInput.blocks[i], funcOutputIdx);
		SymbolIdx fnSymbolIdx = this.symbolTable.declSymbols[funcInput.sourceDeclIdx];
		CompTypeInfo returnType = this.symbolTable.symbols[fnSymbolIdx].type;
		this.lower_terminator(this.mirInput.blocks[i].terminator, loweredBlockIdx, returnType);
	}
	funcOutput.layoutEnd = this.fun_frame_slots_len();
	funcOutput.blocksEnd = this.blocks_len();
	funcOutput.frameSize = common::align_offset(this.localFrameOffset, 8);
}


fn BCBlockIdx BCGenerator.lower_block(BCGenerator* this, MirBlock* mirBlock, BCFunctionIdx currentFuncidx)
{
    BCInstructionIdx instructionsLenBeforeLower = this.instructions_len();
	for(int i = mirBlock.instructionsStart; i<mirBlock.instructionsEnd;i++){
		MirInstruction* mirInstruction = &this.mirInput.instructions[i];
		debug::@log_bytecode("lowering %s | type: %s", mirInstruction.opCode, mirInstruction.type.type);
		switch (mirInstruction.opCode){
			case MirOpCode.EQ:		    this.lower_cmp_op(BCOpCodeCategory.EQ, mirInstruction);
			case MirOpCode.NEQ:		    this.lower_cmp_op(BCOpCodeCategory.NEQ, mirInstruction);
			case MirOpCode.LESS:		this.lower_cmp_op(BCOpCodeCategory.LESS, mirInstruction);
			case MirOpCode.GREATER:		this.lower_cmp_op(BCOpCodeCategory.GREATER, mirInstruction);
			case MirOpCode.ADD:			this.lower_math_op(BCOpCodeCategory.ADD, mirInstruction);
			case MirOpCode.SUB:			this.lower_math_op(BCOpCodeCategory.SUB, mirInstruction);
			case MirOpCode.MUL:			this.lower_math_op(BCOpCodeCategory.MUL, mirInstruction);
			case MirOpCode.DIV:			this.lower_math_op(BCOpCodeCategory.DIV, mirInstruction);
			case MirOpCode.ECHO:		this.lower_echo(mirInstruction);
			case MirOpCode.STORE:
			{
				MirOperand dest = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand source = this.mirInput.operands[(sz)mirInstruction.operandsStart + 1];
				MirPlace* place = &this.mirInput.places[dest.placeIdx];
				SymbolIdx symbolIdx = place.baseSymbolIdx;
				CompTypeInfo symbolType = this.symbolTable.symbols[symbolIdx].type;
				short destOffset = this.bind_symbol_get_offset(symbolIdx) + this.resolve_projection_get_offset(place.projectionIdx, &symbolType);
				this.store_value(mirInstruction, source, destOffset);
			}
			case MirOpCode.LOAD:
			{
				MirRegisterID dest = mirInstruction.result;
				MirOperand source = this.mirInput.operands[mirInstruction.operandsStart];
				MirPlace* place = &this.mirInput.places[source.placeIdx];
				SymbolIdx symbolIdx = place.baseSymbolIdx;
				CompTypeInfo symbolType = this.symbolTable.symbols[symbolIdx].type;
				short srcOffset = this.bind_symbol_get_offset(symbolIdx) + this.resolve_projection_get_offset(place.projectionIdx, &symbolType);
				short destOffset = this.bind_mir_register_get_offset(dest, mirInstruction.type);
				this.load_value(mirInstruction.type, srcOffset, destOffset);
			}
			case MirOpCode.CALL:
			{
				MirOperand callee = this.mirInput.operands[mirInstruction.operandsStart];
				// Lower all call arguments
				short argsStart = -1;
				short argsEnd = -1;
				short argsCount = 0;
				for(int k = mirInstruction.operandsStart + 1; k < mirInstruction.operandsEnd; k++){
					BCCallArg argument = {};
					BCArgIdx argIdx = this.push_callarg_get_idx(&argument);
					if(argsCount == 0){
						argsStart = argIdx;
					}
					// Only way to extract the type for every argument is through symbol table (for now)
					DeclParamRange paramRange = this.symbolTable.declParamRanges[callee.fnCalleeIdx];
					SymbolIdx paramSymbolIdx = this.symbolTable.declParamSymbols[(sz)paramRange.start + argsCount];
					CompTypeInfo argType = this.symbolTable.symbols[paramSymbolIdx].type;
					// Argumnents have bindings in both caller and callee.
					this.bcOutput.callArgs[argIdx].callerOffset = this.bind_operand_get_offset(this.mirInput.operands[k], argType);
					this.bcOutput.callArgs[argIdx].size = (short)compiler::get_type_size(argType);
					this.bcOutput.callArgs[argIdx].type = argType.type;
					argsCount++;
				}
				argsEnd = argsStart + argsCount;
				// Create call info
				BCCallInfo callInfo = {
					.calleeIdx = this.declToBcFunction[callee.fnCalleeIdx],
					.argsStart = argsStart,
					.argsEnd = argsEnd,
					.returnDestOffset = this.bind_mir_register_get_offset(mirInstruction.result, mirInstruction.type),
					.returnSize = (short)compiler::get_type_size(mirInstruction.type)
				};
				BCCallInfoIdx infoIdx = this.push_callinfo_get_idx(&callInfo);
				BCInstruction instruction = {
					.destOffset = this.bind_mir_register_get_offset(mirInstruction.result, mirInstruction.type),
					.leftOffset = runtime::NO_OFFSET,
					.rightOffset = runtime::NO_OFFSET,
					.opCode = BCOpCode.CALL,
					.callInfoIdx = infoIdx,
					.immKind = BCOperandKind.FUNCTION,
				};
				this.push_instruction_get_idx(&instruction);
			}
			default:
			{
				log::errlogn("Instruction \"%s\" is unsupported by compiler", mirInstruction.opCode);
			}
		}
	}
    BCBlock block = {
        .instructionsStart = instructionsLenBeforeLower,
        .instructionsEnd = this.instructions_len()
    };
    return this.push_block_get_idx(&block);
}


fn void BCGenerator.store_value(BCGenerator* this, MirInstruction* mirInstruction, MirOperand val, short destOffset)
{
	BCInstruction instruction = {};
	switch (val.kind) {
		case MirOperandKind.REGISTER:
		{
			ushort bytesToMove = 0;
			BCOpCode opCode = select_mov_op_code(mirInstruction.type, &bytesToMove);
			short srcOffset = this.mirRegToOffset[val.regId];
			instruction.destOffset = destOffset;
			instruction.leftOffset = srcOffset;
			instruction.rightOffset = runtime::NO_OFFSET;
			instruction.opCode = opCode;
			instruction.byteCount = bytesToMove;
			instruction.immKind = opCode == BCOpCode.MOV_BYTES ? BCOperandKind.MOVE_SIZE: BCOperandKind.INVALID;
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
		case MirOperandKind.IMM_FLOAT:
		{
			instruction.destOffset = destOffset;
			instruction.leftOffset = runtime::NO_OFFSET;
			instruction.rightOffset = runtime::NO_OFFSET;
			instruction.immFloat = val.immFloat;
			instruction.opCode = BCOpCode.CONSTF;
			instruction.immKind = BCOperandKind.IMM_FLOAT;
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
		case MirOperandKind.IMM_BOOL:
		{
			instruction.destOffset = destOffset;
			instruction.leftOffset = runtime::NO_OFFSET;
			instruction.rightOffset = runtime::NO_OFFSET;
			instruction.immBool = val.immBool;
			instruction.opCode = BCOpCode.CONSTB;
			instruction.immKind = BCOperandKind.IMM_BOOL;
		}
		default:
		{
			log::errlogn("Unsupported store op for %s", val.kind);
			unreachable();
		}
	}
	this.bcOutput.instructions.push(instruction);

}

fn void BCGenerator.load_value(BCGenerator* this, CompTypeInfo typeInfo, short srcOffset, short destOffset)
{
	ushort bytesToMove = 0;
	BCOpCode opCode = select_mov_op_code(typeInfo, &bytesToMove);
	BCInstruction instruction = {
		.destOffset = destOffset,
		.leftOffset = srcOffset,
		.rightOffset = runtime::NO_OFFSET,
		.immInt = runtime::NO_OFFSET,
		.opCode = opCode,
		.byteCount = bytesToMove,
		.immKind = opCode == BCOpCode.MOV_BYTES ? BCOperandKind.MOVE_SIZE: BCOperandKind.INVALID,
	};
	this.bcOutput.instructions.push(instruction);
}

fn void BCGenerator.lower_echo(BCGenerator* this, MirInstruction* mirInstruction)
{
    MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
    // Bind what we're trying to "echo" to a specific offset in the current stack-frame slots
    short leftOffset = this.bind_operand_get_offset(left, mirInstruction.type);
    BCOpCode finalOpCode = select_echo_op_code(mirInstruction.type);
    BCInstruction instruction = {
        .destOffset = runtime::NO_OFFSET,
        .leftOffset = leftOffset,
        .rightOffset = runtime::NO_OFFSET,
        .immInt = runtime::NO_OFFSET,
        .opCode = finalOpCode,
        .immKind = BCOperandKind.INVALID,
    };
    this.bcOutput.instructions.push(instruction);
}


fn void BCGenerator.lower_math_op(BCGenerator* this, BCOpCodeCategory opCodeCategory, MirInstruction* mirInstruction)
{	
	MirRegisterID mirResult = mirInstruction.result;
	MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
	MirOperand right = this.mirInput.operands[(sz)mirInstruction.operandsStart + 1];
	// Bind operands to specific offsets in the current stack-frame slots
	short leftOffset = this.bind_operand_get_offset(left, mirInstruction.type);
	short rightOffset = this.bind_operand_get_offset(right, mirInstruction.type);
	short destOffset = this.bind_mir_register_get_offset(mirResult, mirInstruction.type);
	BCOpCode finalOpCode = select_math_op_code(mirInstruction.type, opCodeCategory);
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


fn void BCGenerator.lower_cmp_op(BCGenerator* this, BCOpCodeCategory opCodeCategory, MirInstruction* mirInstruction)
{	
	MirRegisterID mirResult = mirInstruction.result;
	MirOperand left = this.mirInput.operands[mirInstruction.operandsStart];
	MirOperand right = this.mirInput.operands[(sz)mirInstruction.operandsStart + 1];
	// Create a return type that is always bool, because comparison can never return anything else
	CompTypeInfo boolType = {.structTypeIndex = compiler::NOT_STRUCT, .type = ValueType.BOOL, .refToType = ValueType.NULL};
	// Operand type is assumed to be uniform once we reach byecode (equal types)
	CompTypeInfo operandsType = this.get_type_from_operand(&left);
	// Bind operands to specific offsets in the current stack-frame slots
	short leftOffset = this.bind_operand_get_offset(left, operandsType);
	short rightOffset = this.bind_operand_get_offset(right, operandsType);
	short destOffset = this.bind_mir_register_get_offset(mirResult, boolType);
	BCOpCode finalOpCode = select_cmp_op_code(operandsType, opCodeCategory);
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


fn void BCGenerator.lower_terminator(BCGenerator* this, MirTerminatorIdx terminatorIdx, BCBlockIdx currentBlockIdx, CompTypeInfo typeInfo)
{
	MirTerminator term = this.mirInput.terminators[terminatorIdx];
	short returnSourceOffset = runtime::NO_OFFSET;
    BCInstructionIdx terminatorsStart = this.instructions_len();
	switch(term.opCode)
	{
		case MirTerminatorOp.RETURN:
		{
			if (term.operandsStart < term.operandsEnd) {
				MirOperand returnOperand = this.mirInput.operands[term.operandsStart];
				returnSourceOffset = this.bind_operand_get_offset(returnOperand, typeInfo);
			}

			BCInstruction instruction = {
				.destOffset = runtime::NO_OFFSET,
				.leftOffset = returnSourceOffset,
				.rightOffset = runtime::NO_OFFSET,
				.opCode = BCOpCode.RETURN,
				.immKind = BCOperandKind.INVALID,
			};

			this.bcOutput.instructions.push(instruction);
		}
		case MirTerminatorOp.BRANCH:
		{
            MirOperand condition = this.mirInput.operands[term.operandsStart];
            MirBlockIdx ifBlock = this.mirInput.operands[(sz)term.operandsStart + 1].blockIdx;
            MirBlockIdx elseBlock = this.mirInput.operands[(sz)term.operandsStart + 2].blockIdx;
            CompTypeInfo conditionType = {.structTypeIndex = compiler::NOT_STRUCT, .type = ValueType.BOOL, .refToType = ValueType.NULL};
            short conditionOffset = this.bind_operand_get_offset(condition, conditionType);
			BCInstruction elseInstruction = {
				.destOffset = runtime::NO_OFFSET,
				.leftOffset = conditionOffset,
				.rightOffset = runtime::NO_OFFSET,
				.opCode = BCOpCode.BRANCH_IF_FALSE,
				.blockToJumpTo = elseBlock,
				.immKind = BCOperandKind.BLOCK,
			};
            BCInstruction thenInstruction = {
                .destOffset = runtime::NO_OFFSET,
                .leftOffset = runtime::NO_OFFSET,
                .rightOffset = runtime::NO_OFFSET,
                .opCode = BCOpCode.JUMP,
                .blockToJumpTo = ifBlock,
                .immKind = BCOperandKind.BLOCK,
            };
            // Push these instruction in "else" then "then" order. 
            // This is because branch is "branch if false", so a true condition should ignore it and continue to the unconditional jump:
	        // BRANCH_IF_FALSE cond, elseBlock
            // UNCONDITIONAL JMP     thenBlock
			this.bcOutput.instructions.push(elseInstruction);
			this.bcOutput.instructions.push(thenInstruction);
		}
		case MirTerminatorOp.JUMP:
		{
            MirBlockIdx destBlock = this.mirInput.operands[term.operandsStart].blockIdx;
            BCInstruction instruction = {
                .destOffset = runtime::NO_OFFSET,
                .leftOffset = runtime::NO_OFFSET,
                .rightOffset = runtime::NO_OFFSET,
                .opCode = BCOpCode.JUMP,
                .blockToJumpTo = destBlock,
                .immKind = BCOperandKind.BLOCK,
            };
            this.bcOutput.instructions.push(instruction);
		}
		default:
		{
			log::errlogn("Unsupported op %s", term.opCode);
			unreachable();
		}
	}
	
	this.bcOutput.blocks[currentBlockIdx].terminatorsStart = terminatorsStart;
	this.bcOutput.blocks[currentBlockIdx].terminatorsEnd = this.instructions_len();
}

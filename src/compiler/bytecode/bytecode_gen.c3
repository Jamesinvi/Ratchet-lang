module compiler::bytecode;
import compiler::analyzer;
import common::stack;
import globals;
import compiler;
import runtime;
import log;
import debug;
import std::collections::list;

faultdef BYTECODE_GEN_ERROR;
enum BCGenResult : char
{
	OK,
	ERROR,
}

struct BCGenerator
{
	ProgramAst* 		inputAst;			// input
	SymbolTable* 		symbolTable;		// input
	MirProgram* 		mirInput;			// input
	BCProgram			bcOutput;			// output
	List{short}			symbolToOffset; 	// temp, Indexed by SymbolIdx
	List{short}			mirRegToOffset;	  	// temp, Indexed by MirRegisterID
	List{CompTypeInfo}  mirRegToType;		// temp, Indexed by MirRegisterID
	Allocator 			outputAllocator;
	int 				currentFrameOffset;
	short 				localFrameOffset;
	bool 				hadError;
}

fn BCProgram? generate_bytecode(ProgramAst* ast, SymbolTable* symbolTable, MirProgram* mirProgram, Allocator outputAllocator)
{
	BCGenerator generator = {};
	generator.init(ast, symbolTable, mirProgram, outputAllocator);
	defer generator.deinit();
	BCGenResult result = generator.run();
	if(result!= BCGenResult.OK){
		return BYTECODE_GEN_ERROR~;
	}
	return generator.bcOutput;
}


fn void BCGenerator.init(BCGenerator* this, ProgramAst* ast, SymbolTable* symbolTable, MirProgram* mirProgram, Allocator outputAllocator)
{
	this.inputAst = ast;
	this.symbolTable = symbolTable;
	this.mirInput = mirProgram;
	this.outputAllocator = outputAllocator;
	this.bcOutput.init(outputAllocator);
	this.symbolToOffset.init(mem);
	this.mirRegToOffset.init(mem);
	this.mirRegToType.init(mem);
}

fn void BCGenerator.deinit(BCGenerator* this)
{
	this.symbolToOffset.free();
	this.mirRegToOffset.free();
	this.mirRegToType.free();
}

fn BCGenResult BCGenerator.run(BCGenerator* this)
{
	// MIR and bytecode functions deliberately use the same stable index.
	foreach(mirFunctionIdx, &func : this.mirInput.functions){
		BCFunction functionResult = {};
		BCFunctionIdx funcIdx = this.push_func_get_idx(&functionResult);
		assert(funcIdx == mirFunctionIdx);
		if (func.sourceMethodIdx == compiler::mir::NO_METHOD) {
			FnDeclAst* sourceFunction = &this.inputAst.declarations[func.sourceDeclIdx].fnDecl;
			String functionName = this.inputAst.names[sourceFunction.nameIdx].text();
			if (functionName == "program") {
				this.bcOutput.entryFunctionIdx = funcIdx;
			}
		}
	}
	// Second pass: actually lower the function instructions
	foreach(funcIdx, &func : this.mirInput.functions){
		this.currentFrameOffset = 0;
		this.localFrameOffset = 0;
		this.prepare_func_bindings(func);
		this.lower_fun(func, (BCFunctionIdx)funcIdx);
	}
	optimize(&this.bcOutput);

	if(this.hadError){
		return BCGenResult.ERROR;
	} else {
		return BCGenResult.OK;
	}
}
	
fn void BCGenerator.lower_fun(BCGenerator* this, MirFunction* funcInput, BCFunctionIdx funcOutputIdx)
{
	BCFunction* funcOutput = &this.bcOutput.functions[funcOutputIdx];
	funcOutput.layoutStart = this.fun_frame_slots_len();

	DeclParamRange params = funcInput.paramRange;
	// Bind all function parameters first! before anything else. 
	// If we don't do this, if a parameter is used after a local, vm will read the wrong offset in the stack frame
	for (int i = params.start; i < params.end; i++) {
		SymbolIdx parameterSymbol =	this.symbolTable.declParamSymbols[i];
		// Reserves and records its offset.
		this.bind_symbol_get_offset(parameterSymbol);
	}

	funcOutput.blocksStart = this.blocks_len();

	for(int i = funcInput.blocksStart; i<funcInput.blocksEnd;i++){
		BCBlockIdx loweredBlockIdx = this.lower_block(&this.mirInput.blocks[i], funcOutputIdx);
		this.lower_terminator(this.mirInput.blocks[i].terminator, loweredBlockIdx, funcInput.returnType);
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
			case MirOpCode.LESS_EQ:		this.lower_cmp_op(BCOpCodeCategory.LESS_EQ, mirInstruction);
			case MirOpCode.GREATER:		this.lower_cmp_op(BCOpCodeCategory.GREATER, mirInstruction);
			case MirOpCode.GREATER_EQ:	this.lower_cmp_op(BCOpCodeCategory.GREATER_EQ, mirInstruction);
			case MirOpCode.AND:			this.lower_cmp_op(BCOpCodeCategory.AND, mirInstruction);
			case MirOpCode.OR:			this.lower_cmp_op(BCOpCodeCategory.OR, mirInstruction);
			case MirOpCode.ADD:			this.lower_math_op(BCOpCodeCategory.ADD, mirInstruction);
			case MirOpCode.SUB:			this.lower_math_op(BCOpCodeCategory.SUB, mirInstruction);
			case MirOpCode.MUL:			this.lower_math_op(BCOpCodeCategory.MUL, mirInstruction);
			case MirOpCode.DIV:			this.lower_math_op(BCOpCodeCategory.DIV, mirInstruction);
			case MirOpCode.ECHO:		this.lower_echo(mirInstruction);
			case MirOpCode.AS:
			{
				MirOperand source =	this.mirInput.operands[mirInstruction.operandsStart];
				CompTypeInfo sourceType = this.get_type_from_operand(&source);
				CompTypeInfo targetType = mirInstruction.type;

				short sourceOffset = this.bind_operand_get_offset(source, sourceType);
				short destinationOffset = this.bind_mir_register_get_offset( mirInstruction.result, targetType);
				BCInstruction instruction = {
					.opCode = BCOpCode.CAST,
					.leftOffset = sourceOffset,
					.rightOffset = runtime::NO_OFFSET,
					.destOffset = destinationOffset,
					.castKind = select_cast_kind(sourceType, targetType),
					.immKind = BCOperandKind.CAST_TYPE,
				};
				this.push_instruction_get_idx(&instruction);
			}
			case MirOpCode.STORE:
			{
				MirOperand dest = this.mirInput.operands[mirInstruction.operandsStart];
				MirOperand source = this.mirInput.operands[(sz)mirInstruction.operandsStart + 1];
				MirPlace* place = &this.mirInput.places[dest.placeIdx];
				SymbolIdx symbolIdx = place.baseSymbolIdx;
				CompTypeInfo symbolType = this.symbolTable.symbols[symbolIdx].type;
				// destOffset = base offset + sum of all projection offsets
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
				// destOffset = base offset + sum of all projection offsets
				short srcOffset = this.bind_symbol_get_offset(symbolIdx) + this.resolve_projection_get_offset(place.projectionIdx, &symbolType);
				short destOffset = this.bind_mir_register_get_offset(dest, mirInstruction.type);
				this.load_value(mirInstruction.type, srcOffset, destOffset);
			}
			case MirOpCode.CALL:
			{
				MirOperand callee = this.mirInput.operands[mirInstruction.operandsStart];
				MirFunction* calleeFunction = &this.mirInput.functions[callee.fnCalleeIdx];
				// Lower all call arguments
				short argsStart = -1;
				short argsEnd = -1;
				short argsCount = 0;
				short calleeParamOffset = 0;
				for(int k = mirInstruction.operandsStart + 1; k < mirInstruction.operandsEnd; k++){
					BCCallArg argument = {};
					BCArgIdx argIdx = this.push_callarg_get_idx(&argument);
					if(argsCount == 0){
						argsStart = argIdx;
					}
					DeclParamRange paramRange = calleeFunction.paramRange;
					SymbolIdx paramSymbolIdx = this.symbolTable.declParamSymbols[(sz)paramRange.start + argsCount];
					Symbol* paramSymbol = &this.symbolTable.symbols[paramSymbolIdx];
					CompTypeInfo argType = paramSymbol.type;
					short argAlignment = (short)compiler::get_type_alignment(argType);
					calleeParamOffset = common::align_offset(calleeParamOffset, argAlignment);
					// Argumnents have bindings in both caller and callee.
					this.bcOutput.callArgs[argIdx].callerOffset = this.bind_operand_get_offset(this.mirInput.operands[k], argType);
					this.bcOutput.callArgs[argIdx].size = (short)compiler::get_type_size(argType);
					this.bcOutput.callArgs[argIdx].type = argType.type;
					this.bcOutput.callArgs[argIdx].calleeOffset = calleeParamOffset;
					this.bcOutput.callArgs[argIdx].copyBack = paramSymbol.passMode == ParamPassMode.INOUT;
					calleeParamOffset += this.bcOutput.callArgs[argIdx].size;
					argsCount++;
				}
				argsEnd = argsStart + argsCount;
				short returnDestOffset = runtime::NO_OFFSET;
				short returnSize = 0;
				if (mirInstruction.type.type != ValueType.NULL) {
					returnDestOffset = this.bind_mir_register_get_offset(mirInstruction.result, mirInstruction.type);
					returnSize = (short)compiler::get_type_size(mirInstruction.type);
				}
				// Create call info
				BCCallInfo callInfo = {
					.calleeIdx = callee.fnCalleeIdx,
					.argsStart = argsStart,
					.argsEnd = argsEnd,
					.returnDestOffset = returnDestOffset,
					.returnSize = returnSize,
				};
				BCCallInfoIdx infoIdx = this.push_callinfo_get_idx(&callInfo);
				BCInstruction instruction = {
					.destOffset = returnDestOffset,
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
		case MirOperandKind.IMM_STRING:
		{
			instruction.destOffset = destOffset;
			instruction.leftOffset = runtime::NO_OFFSET;
			instruction.rightOffset = runtime::NO_OFFSET;
			instruction.immString = val.immString;
			instruction.opCode = BCOpCode.CONSTS;
			instruction.immKind = BCOperandKind.IMM_STRING;
		}
		default:
		{
			log::errlogn("Unsupported store op for %s", val.kind);
			this.hadError = true;
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
			this.hadError = true;
		}
	}
	
	this.bcOutput.blocks[currentBlockIdx].terminatorsStart = terminatorsStart;
	this.bcOutput.blocks[currentBlockIdx].terminatorsEnd = this.instructions_len();
}

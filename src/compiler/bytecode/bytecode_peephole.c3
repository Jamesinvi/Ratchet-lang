module compiler::bytecode;
import runtime;

fn void optimize(BCProgram* input)
{
	optimize_math_and_cmp_ops(input);
}

fn void optimize_math_and_cmp_ops(BCProgram* input)
{

	// NOTE: THIS IS TEMPORARY CODE. IT WORKS BUT IT'S TERRIBLE.
	// Known bytecode patterns are replaced with optimized versions.
	// All ops that are no longer valid, are replaced with NO_OP, so the vm skips it 

	for(BCInstructionIdx i = 0; i < (int)input.instructions.len() - 1; i++){
		BCInstruction* instructionOne = &input.instructions[i];
		BCInstruction* instructionTwo = &input.instructions[(sz)i + 1];
		if(i < (int)input.instructions.len() - 3){
			BCInstruction* instructionThree = &input.instructions[(sz)i + 2];
			BCInstruction* instructionFour = &input.instructions[(sz)i + 3];
			if(instructionOne.opCode == BCOpCode.MOVI 
				&& instructionTwo.opCode == BCOpCode.CONSTI
				&& instructionThree.opCode == BCOpCode.ADDI
				&& instructionFour.opCode == BCOpCode.MOVI
				&& instructionTwo.immInt == 1
				&& instructionThree.leftOffset == instructionOne.destOffset
				&& instructionThree.rightOffset == instructionTwo.destOffset
				&& instructionFour.leftOffset == instructionThree.destOffset
				&& instructionFour.destOffset == instructionOne.leftOffset)
			{
				BCInstruction newInstruction = {
					.opCode = BCOpCode.INCREMENT,
					.destOffset = instructionOne.leftOffset,
					.leftOffset = runtime::NO_OFFSET,
					.rightOffset = runtime::NO_OFFSET,
					.immKind = BCOperandKind.INVALID,
				};
				*instructionOne = newInstruction;
				*instructionTwo = runtime::NO_OP;
				*instructionThree = runtime::NO_OP;
				*instructionFour = runtime::NO_OP;
				continue;
			}
		}

		if(instructionOne.opCode == BCOpCode.CONSTI && instructionTwo.opCode == BCOpCode.ADDI){
			if(instructionTwo.rightOffset == instructionOne.destOffset){
				BCInstruction newInstruction = {
					.opCode = BCOpCode.ADDI_IM,
					.destOffset = instructionTwo.destOffset,
					.leftOffset = instructionTwo.leftOffset,
					.rightOffset = runtime::NO_OFFSET,
					.immInt = instructionOne.immInt,	
					.immKind = BCOperandKind.IMM_INT,
				};
				*instructionOne = newInstruction;
				*instructionTwo = runtime::NO_OP;
			}
		}

		if(instructionOne.opCode == BCOpCode.CONSTI && instructionTwo.opCode == BCOpCode.LESSI){
			if(instructionTwo.rightOffset == instructionOne.destOffset){
				BCInstruction newInstruction = {
					.opCode = BCOpCode.LESSI_IM,
					.destOffset = instructionTwo.destOffset,
					.leftOffset = instructionTwo.leftOffset,
					.rightOffset = runtime::NO_OFFSET,
					.immInt = instructionOne.immInt,	
					.immKind = BCOperandKind.IMM_INT,
				};
				*instructionOne = newInstruction;
				*instructionTwo = runtime::NO_OP;
			}
		}
	}
}

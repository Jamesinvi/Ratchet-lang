module compiler::mir;
import compiler;


MirOperand placeHolderOperand =  {.kind = MirOperandKind.INVALID, .regId= NO_REG};



fn void MirGenerator.terminate_current_block_with_jump(MirGenerator* this, MirBlockIdx targetBlockIdx)
{
    MirBlock* block = &this.output.blocks[this.currentBlock];
    block.instructionsEnd = this.instructions_len();

    if (block.terminator != NO_TERMINATOR) return;

    OperandIdx jumpStart = this.operands_len();
    this.output.operands.push({ .kind = MirOperandKind.BLOCK, .blockIdx = targetBlockIdx });
    OperandIdx jumpEnd = this.operands_len();

    MirTerminator jumpTerm = {
        .opCode = MirTerminatorOp.JUMP,
        .operandsStart = jumpStart,
        .operandsEnd = jumpEnd,
    };

    block.terminator = this.push_terminator_get_idx(&jumpTerm);
}

fn MirBlockIdx MirGenerator.push_empty_block(MirGenerator* this)
{
    MirBlockIdx idx = this.blocks_len();
    MirBlock block = {
        .idx = idx,
        .instructionsStart = this.instructions_len(),
        .instructionsEnd = this.instructions_len(),
        .terminator = NO_TERMINATOR,
    };
    this.output.blocks.push(block);
    return idx;
}


fn MirOpCode ast_to_mir_op(BinOp astBinOp) @inline
{
	return (MirOpCode)(int)astBinOp;
}

fn MirPlaceIdx MirGenerator.push_place_get_idx(MirGenerator* this, MirPlace* to_push)
{
    MirPlaceIdx index = (MirPlaceIdx)this.output.places.len();
    to_push.idx = index;
    this.output.places.push(*to_push);
    return index;
}

fn MirProjectionIdx MirGenerator.push_projection_get_idx(MirGenerator* this, MirProjection* to_push)
{
    MirProjectionIdx index = (MirProjectionIdx)this.output.projections.len();
    this.output.projections.push(*to_push);
    return index;
}

fn MirTerminatorIdx MirGenerator.push_terminator_get_idx(MirGenerator* this, MirTerminator* to_push)
{
    MirTerminatorIdx index = (MirTerminatorIdx)this.output.terminators.len();
    this.output.terminators.push(*to_push);
    return index;
}

macro MirInstructionIdx MirGenerator.instructions_len(MirGenerator* this)
{
    assert(this.output.instructions.len() < int::max);
    return (MirInstructionIdx)this.output.instructions.len();
}


macro MirBlockIdx MirGenerator.blocks_len(MirGenerator* this)
{
    assert(this.output.blocks.len() < int::max);
    return (MirBlockIdx)this.output.blocks.len();
}

macro OperandIdx MirGenerator.operands_len(MirGenerator* this)
{
    assert(this.output.operands.len() < int::max);
    return (OperandIdx)this.output.operands.len();
}

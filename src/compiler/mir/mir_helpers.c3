module compiler::mir;
import compiler;


MirOperand placeHolderOperand =  {.kind = MirOperandKind.INVALID, .regId= NO_REG};


fn void MirGenerator.terminate_current_block_with_jump(MirGenerator* this, MirBlockIdx targetBlockIdx)
{
    this.seal_current_block();
    this.add_jump_to_current_block(targetBlockIdx);
}

<* 
	Simply sets the instructionsEnd field to the current block
*>
fn void MirGenerator.seal_current_block(MirGenerator* this)
{
    MirBlock* block = &this.output.blocks[this.currentBlock];
    block.instructionsEnd = this.instructions_len();
}

fn void MirGenerator.add_jump_to_current_block(MirGenerator* this, MirBlockIdx targetBlockIdx)
{
    MirBlock* block = &this.output.blocks[this.currentBlock];
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

fn MirBlockIdx MirGenerator.push_empty_block_get_idx(MirGenerator* this)
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

fn MirOperand MirGenerator.get_or_bind_place(MirGenerator* this, SymbolIdx symbolIdx)
{
    MirOperand place = this.bindings[symbolIdx];
    if (place.kind == MirOperandKind.PLACE) {
        return place;
    }

    Symbol* symbol = &this.symbolTable.symbols[symbolIdx];
    assert(symbol.kind == SymbolKind.GLOBAL_VAR);

    MirPlace globalPlace = {
        .baseSymbolIdx = symbolIdx,
        .projectionIdx = NO_PROJECTION,
        .isGlobal = true,
    };
    MirPlaceIdx placeIdx = this.push_place_get_idx(&globalPlace);

    place = {
        .kind = MirOperandKind.PLACE,
        .placeIdx = placeIdx,
    };
    this.bindings[symbolIdx] = place;
    return place;
}




fn MirOpCode ast_to_mir_op(BinOp astBinOp) @inline
{
    switch (astBinOp) {
        case BinOp.ADD:        return MirOpCode.ADD;
        case BinOp.SUB:        return MirOpCode.SUB;
        case BinOp.MUL:        return MirOpCode.MUL;
        case BinOp.DIV:        return MirOpCode.DIV;
        case BinOp.EQ:         return MirOpCode.EQ;
        case BinOp.NEQ:        return MirOpCode.NEQ;
        case BinOp.LESS:       return MirOpCode.LESS;
        case BinOp.LESS_EQ:    return MirOpCode.LESS_EQ;
        case BinOp.GREATER:    return MirOpCode.GREATER;
        case BinOp.GREATER_EQ: return MirOpCode.GREATER_EQ;
        case BinOp.AND:        return MirOpCode.AND;
        case BinOp.OR:         return MirOpCode.OR;
        case BinOp.STORE:      return MirOpCode.STORE;
    }
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

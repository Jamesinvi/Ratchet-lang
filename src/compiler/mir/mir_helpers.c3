module mir;
import parser;

MirOperand placeHolderOperand =  {.kind = MirOperandKind.INVALID, .as.regId= NO_REG};

fn MirOpCode ast_to_mir_op(BinOp astBinOp) @inline
{
	return (MirOpCode)(int)astBinOp;
}


fn MirPlaceIdx MirGenerator.push_place_get_idx(MirGenerator* this, MirPlace* to_push)
{
    MirPlaceIdx index = this.output.places.len();
    to_push.idx = index;
    this.output.places.push(*to_push);
    return index;
}

fn MirProjectionIdx MirGenerator.push_projection_get_idx(MirGenerator* this, MirProjection* to_push)
{
    MirProjectionIdx index = this.output.projections.len();
    this.output.projections.push(*to_push);
    return index;
}

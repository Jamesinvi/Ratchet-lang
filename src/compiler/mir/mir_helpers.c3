module mir;
import parser;

MirOperand placeHolderOperand =  {.kind = MirOperandKind.INVALID, .as.regId= NO_REG};

fn MirOpCode ast_to_mir_op(BinOp astBinOp) @inline
{
	return (MirOpCode)(int)astBinOp;
}
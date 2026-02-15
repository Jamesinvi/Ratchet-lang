module mir;
import parser;

MirOperand placeHolderOperand =  {.kind = MirOperandKind.INVALID, .as.regId= NO_REG};

fn MirOpCode ast_to_mir_op(BinOp astBinOp) @inline
{
	return (MirOpCode)(int)astBinOp;
}

fn String mangle_method_name(ProgramAst* ast, DeclIdx structDeclIdx, int methodIdx, Allocator allocator)
{
    Decl* structDecl = &ast.declarations[structDeclIdx];
    MethodDeclAst* methodDecl = &structDecl.structDecl.methods[methodIdx];
    String structName = ast.names[structDecl.structDecl.nameIdx];
    String methodName = ast.names[methodDecl.nameIdx];

    return string::format(allocator, "%s_%s", structName, methodName);
}

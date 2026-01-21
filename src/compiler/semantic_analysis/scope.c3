module parser;
import common;
import debug;


struct Scope
{
    Local[Byte.max] locals;
    int localCount;
    int depth;
    TypeResult returnType;
    usz enclosingIdx;
	bool insideMethod;
	Stack{SymbolIdx} visibleSymbols;
}

fn void Scope.init(Scope* this, TypeResult returnType, bool insideMethod){
    debug::@log_compilation("initializing new scope");
    this.depth = 0;
    this.localCount = 0;
	this.returnType = returnType;
	this.insideMethod = insideMethod;

    // Dummy local 0 for this function
    Local* local = &this.locals[this.localCount++];
    local.depth      = 0;
    local.name.value = "";


}

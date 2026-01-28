module parser;
import common;
import debug;


struct Scope
{
    TypeResult returnType;
    usz enclosingIdx;
	usz depth;
	bool insideMethod;
	Stack{SymbolIdx} visibleSymbols;
}

fn void Scope.init(Scope* this, TypeResult returnType, bool insideMethod){
    debug::@log_analysis("initializing new scope");
	this.returnType = returnType;
	this.insideMethod = insideMethod;
}

fn void Scope.deinit(Scope* this)
{
	this.visibleSymbols.free();
}

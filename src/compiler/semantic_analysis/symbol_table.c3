module parser::analyzer;
import std::collections::list;

alias SymbolIdx = usz;
const NO_SYMBOL = usz.max;

enum SymbolKind : char
{
	LOCAL,
	FUNCTION,
	FIELD,
	PARAM,
}

struct Symbol
{
	SymbolKind kind;
	SymbolIdx idx;
	CompTypeInfo type;
}

struct SymbolTable
{
	List{Symbol} symbols;
    List{SymbolIdx} exprSymbols; 	// index by ExprIdx
    List{SymbolIdx} stmtSymbols; 	// index by StmtIdx
    List{SymbolIdx} declSymbols; 	// index by DeclIdx
    List{Scope} scopes;         	// name -> SymbolIdx
}

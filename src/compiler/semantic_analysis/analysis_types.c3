module parser::analyzer;
import std::collections::list;
import common;
import debug;


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
    List{SymbolIdx} exprSymbols; 		// index by ExprIdx
    List{CompTypeInfo} exprTypes; 		// index by ExprIdx
    List{SymbolIdx} stmtSymbols; 		// index by StmtIdx
    List{SymbolIdx} declSymbols; 		// index by DeclIdx
    List{CallTarget} callTargets;		// index by ExprIdx
    List{ExprIdx} callReceiverExpr; 	// index by ExprIdx (NO_IDX when absent)
    List{Scope} scopes;         		// name -> SymbolIdx
}


enum CallTargetKind : char
{
	INVALID,
	FREE_FUN,
	METHOD,
}

struct CallTarget
{
	CallTargetKind kind;
	DeclIdx fnDeclIdx;
}

struct MethodId
{
	DeclIdx structDeclIdx;
	int methodIdx;
}

enum ErrorKind : char (String asStr)
{
	TYPE_MISMATCH	= "Type mismatch",
	INVALID_TYPE	= "Invalid type",
	UNDECLARED_NAME	= "Undeclared name",
	NO_RETURN		= "No return",
}

struct TypeResult
{
	CompTypeInfo value;
	CompTypeInfo expected;
	bool hadError;
	ErrorKind errKind;
	Span errSpan;
}

fn TypeResult type_ok(CompTypeInfo expected)
{
	TypeResult result = {};
	result.value = expected;
	result.expected = expected;
	result.hadError = false;
	return result;
}

fn TypeResult SemanticAnalyzer.type_error(SemanticAnalyzer* this, ErrorKind kind, CompTypeInfo value, CompTypeInfo expected, Span span)
{
	TypeResult result = {};
	result.hadError = true;
	result.value = value;
	result.expected = expected;
	result.errKind = kind;
	result.errSpan = span;
	this.errors.push(result);
	return result;
}

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

module compiler::analyzer;
import std::collections::list;
import compiler;
import common;
import debug;


alias SymbolIdx = int;
alias MemberIdx = int;
const NO_SYMBOL = -1;

enum SymbolKind : char
{
	LOCAL,
	FUNCTION,
	FIELD,
	PARAM,
	RECEIVER,
}

struct Symbol
{
	SymbolIdx idx;
	CompTypeInfo type;
	SymbolKind kind;
	ParamPassMode passMode;
}

struct DeclParamRange
{
	int start;
	int end;
}

struct SymbolTable
{
	List{Symbol} symbols;
	List{SymbolIdx} exprSymbols; 			// index by ExprIdx
	List{CompTypeInfo} exprTypes; 			// index by ExprIdx
	List{SymbolIdx} stmtSymbols; 			// index by StmtIdx
	List{SymbolIdx} declSymbols; 			// index by DeclIdx
	List{DeclParamRange} declParamRanges; 	// index by DeclIdx
	List{MemberIdx} memberFieldIndices; 	// indexed by ExprIdx, -1 if not a member expr
	List{SymbolIdx} declParamSymbols; 		// flat storage for function param symbols
	List{CallTarget} callTargets; 			// index by ExprIdx
	List{ExprIdx} callReceiverExpr; 		// index by ExprIdx (NO_IDX when absent)
	List{Scope} scopes; 					// name -> SymbolIdx
	List{MethodAnalysisInfo} methods;		// semantic data for source methods
}

fn MethodAnalysisInfo* SymbolTable.find_method(SymbolTable* this, MethodId id)
{
	foreach (&method : this.methods) {
		if (method.id.structDeclIdx == id.structDeclIdx && method.id.methodIdx == id.methodIdx) {
			return method;
		}
	}
	return null;
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
	MethodId methodId;
}

struct MethodId
{
	DeclIdx structDeclIdx;
	int methodIdx;
}

struct MethodAnalysisInfo
{
	MethodId id;
	DeclParamRange paramRange;	// receiver is always parameter 0
	SymbolIdx receiverSymbolIdx;
	CompTypeInfo returnType;
}


enum ErrorKind : char (String asStr)
{
	TYPE_MISMATCH   	{ "Type mismatch" },
	UNRESOLVED_STRUCT	{ "Struct type was unresolved. Circular reference?"},
	INVALID_TYPE    	{ "Invalid type" },
	INVALID_LVALUE  	{ "Invalid lvalue" },
	INVALID_ARITY   	{ "Invalid argument count" },
	UNDECLARED_NAME 	{ "Undeclared name" },
	NO_RETURN       	{ "No return" },
}

struct TypeResult
{
	CompTypeInfo value;
	CompTypeInfo expected;
	Span errSpan;
	ErrorKind errKind;
	bool hadError;
}

fn TypeResult type_ok(CompTypeInfo expected)
{
	TypeResult result = { };
	result.value = expected;
	result.expected = expected;
	result.hadError = false;
	return result;
}

fn TypeResult SemanticAnalyzer.type_error(
	SemanticAnalyzer* this,
	ErrorKind kind,
	CompTypeInfo value,
	CompTypeInfo expected,
	Span span
)
{
	TypeResult result = { };
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
	Stack{SymbolIdx} visibleSymbols;
	int enclosingIdx;
	int depth;
	bool insideMethod;
}

fn void Scope.init(Scope* this, TypeResult returnType, bool insideMethod)
{
	debug::@log_analysis("initializing new scope");
	this.returnType = returnType;
	this.insideMethod = insideMethod;
}

fn void Scope.deinit(Scope* this)
{
	this.visibleSymbols.free();
}

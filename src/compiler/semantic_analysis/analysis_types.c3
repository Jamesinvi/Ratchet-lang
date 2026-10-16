module compiler::analyzer;
import std::collections::list;
import std::collections::map;
import compiler;
import common;
import debug;


alias SymbolIdx = int;
alias MemberIdx = int;
alias NativeFnIdx = int;
alias FuncIdx = int;
const NO_SYMBOL = -1;

enum SymbolKind : char
{
	LOCAL,
	FUNCTION,
	FIELD,
	PARAM,
	RECEIVER,
	GLOBAL_VAR,
}

struct Symbol
{
	union
	{
		ExprIdx exprIdx;
		DeclIdx declIdx;
		StmtIdx stmtIdx;
		FuncIdx funcIdx; // index into SymbolTable.functions for FUNCTION symbols
	}
	InternedString name;
	TypeInfo type;
	SymbolKind kind;
	ParamPassMode passMode;
}

struct SymbolTable
{
	List{Symbol} symbols; // index by SymbolIdx
	List{SymbolIdx} exprSymbols; // index by ExprIdx
	List{TypeInfo} exprTypes; // index by ExprIdx
	List{SymbolIdx} stmtSymbols; // index by StmtIdx
	List{SymbolIdx} declSymbols; // index by DeclIdx
	HashMap{ExprIdx, MemberIdx} memberFieldIndices;
	HashMap{ExprIdx, CallTarget} callTargets;
	List{FunctionAnalysisInfo} functions; // index by FuncIdx
}

fn TypeInfo SymbolTable.get_expression_type(SymbolTable* this, ExprIdx exprIdx) @inline
{
	return this.exprTypes[exprIdx];
}

fn FunctionAnalysisInfo* SymbolTable.find_method(SymbolTable* this, MethodId id)
{
	foreach (&function : this.functions)
	{
		if (function.kind != CallTargetKind.METHOD) continue;
		if (function.methodId.structDeclIdx == id.structDeclIdx && function.methodId.methodIdx == id.methodIdx) return function;
	}
	return null;
}

struct FunctionAnalysisInfo
{
	SymbolIdx symbolIdx;
	TypeInfo returnType;
	union
	{
		DeclIdx fnDeclIdx;
		NativeFnIdx nativeFnIdx;
		MethodId methodId;
	}
	SymbolIdx receiverSymbolIdx;
	SymbolIdx[] params;
	CallTargetKind kind;
}

struct CallTarget
{
	SymbolIdx functionSymbolIdx;
	ExprIdx receiverExprIdx; // NO_IDX for free calls and implicit this
}

struct MethodId
{
	DeclIdx structDeclIdx;
	int methodIdx;
}


enum ErrorKind : char (String asStr)
{
	TYPE_MISMATCH              { "Type mismatch" },
	UNRESOLVED_STRUCT          { "Struct type was unresolved. Circular reference?" },
	INVALID_TYPE               { "Invalid type" },
	INVALID_LVALUE             { "Invalid lvalue" },
	INVALID_ARITY              { "Invalid argument count" },
	UNDECLARED_NAME            { "Undeclared name" },
	NO_RETURN                  { "No return" },
	INVALID_GLOBAL_INITIALIZER { "Global initializer must be a constant value" },
	CONTINUE_WITHOUT_LOOP      { "\"continue\" statement is only allowed inside a loop" },
	BREAK_WITHOUT_LOOP         { "\"break\" statement is only allowed inside a loop" },
	NOT_INDEXABLE              { "Cannot index" },
	INVALID_METHOD_RECEIVER    { "Method receiver must be a variable or field; store temporary results in a variable first" },
	MEMBER_IS_READONLY         { "Member is readonly" },
	INVALID_CALL               { "Unknown function or method" },
	PASS_MODE_MISMATCH         { "In/Inout modifiers must match between function definition and function call" },
	FUNC_NAME_CLASHES_NATIVE   { "Function name clashes with built-in function" },
}

struct TypeResult
{
	TypeInfo value;
	TypeInfo expected;
	Span errSpan;
	ErrorKind errKind;
	bool hadError;
}

fn TypeResult type_ok(TypeInfo expected)
{
	TypeResult result = { };
	result.value = expected;
	result.expected = expected;
	result.hadError = false;
	return result;
}

fn TypeResult SemanticAnalyzer.type_error(SemanticAnalyzer* this, ErrorKind kind, TypeInfo value, TypeInfo expected, Span span)
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


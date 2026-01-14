module parser::analyzer;

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

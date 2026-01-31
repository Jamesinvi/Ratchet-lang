module common;
import globals;
import log;
import std::collections::list;

enum TokenType : uint {
    // Single-character tokens.
    LEFT_PAREN, RIGHT_PAREN, LEFT_BRACE, RIGHT_BRACE,
    COMMA, DOT, MINUS, PLUS, SEMICOLON, SLASH, STAR,

    // One or two character tokens.
    BANG, BANG_EQUAL, EQUAL, EQUAL_EQUAL,
    GREATER, GREATER_EQUAL, LESS, LESS_EQUAL,

    // Literals.
    IDENTIFIER, STRING, INTEGER, FLOAT, DOUBLE,

    // Keywords.
    AND, CLASS, ELSE, FALSE, FN, FOR, IF, NULL, OR,
    PRINT, RETURN, SUPER, THIS, TRUE, WHILE, ECHO,
    METHOD, AS, NEW,

    // Types
    INTEGER_T, FLOAT_T, DOUBLE_T, STRING_T, STRUCT_T, BOOL_T,
    INT_REF_GC, FLOAT_REF_GC, DOUBLE_REF_GC, BOOL_REF_GC,
    INT_REF_NOGC, FLOAT_REF_NOGC, DOUBLE_REF_NOGC, BOOL_REF_NOGC,
    EOF,
}

struct Keyword
{
    TokenType tokenType;
    String string;
}
struct Token 
{
    TokenType tokenType;
    int line;
	usz valueIdx;			// Index in a list of strings
}


fn String Token.value(Token* this)
{
	return globals::tokenValues[this.valueIdx];
}

Keyword[*] keywords = {
    {.tokenType = AND, .string = "and"},
    {.tokenType = ELSE, .string = "else"},
    {.tokenType = FALSE, .string = "false"},
    {.tokenType = FN, .string = "fn"},
    {.tokenType = FOR, .string = "for"},
    {.tokenType = IF, .string = "if"},
    {.tokenType = NULL, .string = "null"},
    {.tokenType = OR, .string = "or"},
    {.tokenType = PRINT, .string = "print"},
    {.tokenType = RETURN, .string = "return"},
    {.tokenType = THIS, .string = "this"},
    {.tokenType = TRUE, .string = "true"},
    {.tokenType = WHILE, .string = "while"},
    {.tokenType = INT_REF_GC, .string = "int&"},
    {.tokenType = FLOAT_REF_GC, .string = "float&"},
    {.tokenType = DOUBLE_REF_GC, .string = "double&"},
    {.tokenType = BOOL_REF_GC, .string = "bool&"},
    {.tokenType = INTEGER_T, .string = "int"},
    {.tokenType = FLOAT_T, .string = "float"},
    {.tokenType = DOUBLE_T, .string = "double"},
    {.tokenType = ECHO, .string = "echo"},
    {.tokenType = STRING_T, .string = "string"},
    {.tokenType = STRUCT_T, .string = "struct"},
    {.tokenType = BOOL_T, .string = "bool"},
    {.tokenType = NEW, .string = "new"},
    {.tokenType = ECHO, .string = "echo"},
    {.tokenType = AS, .string = "as"},
    {.tokenType = METHOD, .string = "method"},
};

// -------------Token based matches--------------

fn bool Token.matches_type(Token* t, TokenType toCheck) @inline
{
    return t.tokenType == toCheck;
}


fn bool Token.is_any_type(Token* t)
{
    return  t.is_builtin_type() 		||
            t.is_struct_type()          ||
            t.is_builtin_ref()   		||
            t.is_builtin_ptr()   		||
            t.is_struct_ref()			||
            t.is_struct_ptr();
}

fn bool Token.is_struct_type(Token* t)
{
    bool typeAlreadyDeclared = str_is_struct_type(t.value());
    return t.matches_type(TokenType.IDENTIFIER) && typeAlreadyDeclared;
}

fn bool Token.is_struct_ref(Token* t)
{
    if (!t.matches_type(TokenType.IDENTIFIER)) return false;

	char tokenLastChar = t.value()[t.value().len-1];
	if(tokenLastChar != '&') return false;
	String refStructName = t.value().[0 .. t.value().len-2];
	return str_is_struct_type(refStructName);
}

fn bool Token.is_struct_ptr(Token* t)
{
    if (!t.matches_type(TokenType.IDENTIFIER)) return false;

	char tokenLastChar = t.value()[t.value().len-1];
	if(tokenLastChar != '*') return false;
	String refStructName = t.value().[0 .. t.value().len-2];
	return str_is_struct_type(refStructName);
}


fn bool str_is_struct_type(String str) @inline
{
	return globals::declaredStructs.has_key(str);
}

// ------------TokenType based matches------------

fn bool TokenType.is_builtin_type(TokenType* t)
{
    return (*t == TokenType.NULL)      ||
           (*t == TokenType.INTEGER_T) ||
           (*t == TokenType.FLOAT_T)   ||
           (*t == TokenType.DOUBLE_T)  ||
           (*t == TokenType.BOOL_T)    ||
           (*t == TokenType.STRING_T);
}

fn bool TokenType.is_builtin_ref(TokenType* t)
{
    return (*t == TokenType.INT_REF_GC)		||
           (*t == TokenType.FLOAT_REF_GC)	||
           (*t == TokenType.DOUBLE_REF_GC)   ||
           (*t == TokenType.BOOL_REF_GC);
}

fn bool TokenType.is_builtin_ptr(TokenType* t)
{
    return (*t == TokenType.INT_REF_NOGC)		||
           (*t == TokenType.FLOAT_REF_NOGC)	||
           (*t == TokenType.DOUBLE_REF_NOGC)   ||
           (*t == TokenType.BOOL_REF_NOGC);
}

fn bool Token.is_builtin_type(Token* t)
{
	return t.tokenType.is_builtin_type();
}

fn bool Token.is_builtin_ref(Token* t)
{
	return t.tokenType.is_builtin_ref();
}

fn bool Token.is_builtin_ptr(Token* t)
{
	return t.tokenType.is_builtin_ptr();
}



module parser;
import common;
import log;


fn bool Token.matches_type(Token* t, TokenType toCheck) @inline
{
    return t.tokenType == toCheck;
}

// -------------Token based matches--------------

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
    bool typeAlreadyDeclared = str_is_struct_type(t.value);
    return t.matches_type(TokenType.IDENTIFIER) && typeAlreadyDeclared;
}

fn bool Token.is_struct_ref(Token* t)
{
    if (!t.matches_type(TokenType.IDENTIFIER)) return false;

	char tokenLastChar = t.value[t.value.len-1];
	if(tokenLastChar != '&') return false;
	String refStructName = t.value.[0 .. t.value.len-2];
	return str_is_struct_type(refStructName);
}

fn bool Token.is_struct_ptr(Token* t)
{
    if (!t.matches_type(TokenType.IDENTIFIER)) return false;

	char tokenLastChar = t.value[t.value.len-1];
	if(tokenLastChar != '*') return false;
	String refStructName = t.value.[0 .. t.value.len-2];
	return str_is_struct_type(refStructName);
}


fn bool str_is_struct_type(String str) @inline
{
	return declaredStructs.has_key(str);
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



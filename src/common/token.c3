module common;
import log;

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
    PRINT, RETURN, SUPER, THIS, TRUE, VAR, WHILE, ECHO,
    METHOD, NEW, AS,

    // Types
    INTEGER_T, FLOAT_T, DOUBLE_T, STRING_T, STRUCT_T, BOOL_T,
    INT_REF_GC, FLOAT_REF_GC, DOUBLE_REF_GC, BOOL_REF_GC,
    INT_REF_NOGC, FLOAT_REF_NOGC, DOUBLE_REF_NOGC, BOOL_REF_NOGC,
    EOF,
}

struct Keyword {
    TokenType tokenType;
    String value;
}
struct Token (DebugPrintable) {
    TokenType tokenType;
    int line;
    String value;
}

fn void Token.debug_print(Token* token) @dynamic{
    log::logn("Token: {type: %s, value: '%s'}",  token.tokenType, token.value);
}

Keyword[*] keywords = {
    {.tokenType = AND, .value = "and"},
    {.tokenType = ELSE, .value = "else"},
    {.tokenType = FALSE, .value = "false"},
    {.tokenType = FN, .value = "fn"},
    {.tokenType = FOR, .value = "for"},
    {.tokenType = IF, .value = "if"},
    {.tokenType = NULL, .value = "null"},
    {.tokenType = OR, .value = "or"},
    {.tokenType = PRINT, .value = "print"},
    {.tokenType = RETURN, .value = "return"},
    {.tokenType = THIS, .value = "this"},
    {.tokenType = TRUE, .value = "true"},
    {.tokenType = WHILE, .value = "while"},
    {.tokenType = INT_REF_GC, .value = "int&"},
    {.tokenType = FLOAT_REF_GC, .value = "float&"},
    {.tokenType = DOUBLE_REF_GC, .value = "double&"},
    {.tokenType = BOOL_REF_GC, .value = "bool&"},
    {.tokenType = INTEGER_T, .value = "int"},
    {.tokenType = FLOAT_T, .value = "float"},
    {.tokenType = DOUBLE_T, .value = "double"},
    {.tokenType = ECHO, .value = "echo"},
    {.tokenType = STRING_T, .value = "string"},
    {.tokenType = STRUCT_T, .value = "struct"},
    {.tokenType = BOOL_T, .value = "bool"},
    {.tokenType = NEW, .value = "new"},
    {.tokenType = ECHO, .value = "echo"},
    {.tokenType = AS, .value = "as"},

};

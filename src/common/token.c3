module common;
import std::io;

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
    AND, CLASS, ELSE, FALSE, FUN, FOR, IF, NULL, OR,
    PRINT, RETURN, SUPER, THIS, TRUE, VAR, WHILE, DEBUG,

    // Types
    INTEGER_T, FLOAT_T, DOUBLE_T, STRING_T,
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
    io::printfn("Token: {type: %s, value: '%s'}",  TokenType.names[(int)token.tokenType], token.value);
}

Keyword[*] keywords = {
    {.tokenType = AND, .value = "and"},
    {.tokenType = CLASS, .value = "class"},
    {.tokenType = ELSE, .value = "else"},
    {.tokenType = FALSE, .value = "false"},
    {.tokenType = FUN, .value = "fn"},
    {.tokenType = FOR, .value = "for"},
    {.tokenType = IF, .value = "if"},
    {.tokenType = NULL, .value = "null"},
    {.tokenType = OR, .value = "or"},
    {.tokenType = PRINT, .value = "print"},
    {.tokenType = RETURN, .value = "return"},
    {.tokenType = SUPER, .value = "super"},
    {.tokenType = THIS, .value = "this"},
    {.tokenType = TRUE, .value = "true"},
    {.tokenType = WHILE, .value = "while"},
    {.tokenType = INTEGER_T, .value = "int"},
    {.tokenType = FLOAT_T, .value = "float"},
    {.tokenType = DOUBLE_T, .value = "double"},
    {.tokenType = DEBUG, .value = "debug"},
    {.tokenType = STRING_T, .value = "string"},
};

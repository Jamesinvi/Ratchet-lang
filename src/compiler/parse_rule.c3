module parser;
import common;

alias PrefixFn = fn ExprIdx(Parser* parser);
alias InfixFn = fn ExprIdx(Parser* parser, ExprIdx lhs);

enum Precedence 
{
    NONE,
    ASSIGNMENT, // =
    AS,
    OR,         // ||
    AND,        // &&
    EQUALITY,   
    COMPARISON, // ==
    TERM,       
    FACTOR,
    UNARY,
    CALL,
    PRIMARY
}


struct ParseRule
{
    PrefixFn prefix;
    InfixFn infix;
    Precedence precedence;
}


fn ParseRule* get_rule(TokenType operator){
    return &rules[(usz)operator];
}
ParseRule[]rules = {
  [TokenType.LEFT_PAREN.ordinal]    = {&Parser.grouping,        &Parser.call,       Precedence.CALL},
  [TokenType.RIGHT_PAREN.ordinal]   = {null,                    null,               Precedence.NONE},
  [TokenType.LEFT_BRACE.ordinal]    = {null,                    null,               Precedence.NONE}, 
  [TokenType.RIGHT_BRACE.ordinal]   = {null,                    null,               Precedence.NONE},
  [TokenType.COMMA.ordinal]         = {null,                    null,               Precedence.NONE},
  [TokenType.DOT.ordinal]           = {null,                    &Parser.dot,        Precedence.CALL},
  [TokenType.MINUS.ordinal]         = {&Parser.unary,           &Parser.binary,     Precedence.TERM},
  [TokenType.PLUS.ordinal]          = {null,                    &Parser.binary,     Precedence.TERM},
  [TokenType.SEMICOLON.ordinal]     = {null,                    null,               Precedence.NONE},
  [TokenType.SLASH.ordinal]         = {null,                    &Parser.binary,     Precedence.FACTOR},
  [TokenType.STAR.ordinal]          = {null,                    &Parser.binary,     Precedence.FACTOR},
  [TokenType.BANG.ordinal]          = {&Parser.unary,           null,               Precedence.NONE},
  [TokenType.BANG_EQUAL.ordinal]    = {null,                    &Parser.binary,     Precedence.EQUALITY},
  [TokenType.EQUAL.ordinal]         = {null,                    &Parser.binary,     Precedence.ASSIGNMENT},
  [TokenType.EQUAL_EQUAL.ordinal]   = {null,                    &Parser.binary,     Precedence.EQUALITY},
  [TokenType.GREATER.ordinal]       = {null,                    &Parser.binary,     Precedence.COMPARISON},
  [TokenType.GREATER_EQUAL.ordinal] = {null,                    &Parser.binary,     Precedence.COMPARISON},
  [TokenType.LESS.ordinal]          = {null,                    &Parser.binary,     Precedence.COMPARISON},
  [TokenType.LESS_EQUAL.ordinal]    = {null,                    &Parser.binary,     Precedence.COMPARISON},
  [TokenType.IDENTIFIER.ordinal]    = {&Parser.variable,        null,               Precedence.NONE},
  [TokenType.STRING.ordinal]        = {&Parser.string,          null,               Precedence.NONE},
  [TokenType.INTEGER.ordinal]       = {&Parser.number,          null,               Precedence.NONE},
  [TokenType.FLOAT.ordinal]         = {&Parser.number,          null,               Precedence.NONE},
  [TokenType.DOUBLE.ordinal]        = {&Parser.number,          null,               Precedence.NONE},
  [TokenType.AND.ordinal]           = {null,                    &Parser.and,        Precedence.AND},
  [TokenType.CLASS.ordinal]         = {null,                    null,               Precedence.NONE},
  [TokenType.ELSE.ordinal]          = {null,                    null,               Precedence.NONE},
  [TokenType.FALSE.ordinal]         = {&Parser.literal_false,   null,               Precedence.NONE},
  [TokenType.FOR.ordinal]           = {null,                    null,               Precedence.NONE},
  [TokenType.FN.ordinal]            = {null,                    null,               Precedence.NONE},
  [TokenType.IF.ordinal]            = {null,                    null,               Precedence.NONE},
  [TokenType.NULL.ordinal]          = {&Parser.literal_null,    null,               Precedence.NONE},
  [TokenType.OR.ordinal]            = {null,                    &Parser.or,         Precedence.OR},
  [TokenType.PRINT.ordinal]         = {null,                    null,               Precedence.NONE},
  [TokenType.RETURN.ordinal]        = {null,                    null,               Precedence.NONE},
  [TokenType.SUPER.ordinal]         = {null,                    null,               Precedence.NONE},
  [TokenType.THIS.ordinal]          = {null,                    null,               Precedence.NONE},
  [TokenType.TRUE.ordinal]          = {&Parser.literal_true,    null,               Precedence.NONE},
  [TokenType.VAR.ordinal]           = {null,                    null,               Precedence.NONE},
  [TokenType.WHILE.ordinal]         = {null,                    null,               Precedence.NONE},
  [TokenType.EOF.ordinal]           = {null,                    null,               Precedence.NONE},
  [TokenType.NEW.ordinal]           = {&Parser.new_expr,        null,               Precedence.NONE},
  [TokenType.AS.ordinal]            = {null,                    &Parser.as,         Precedence.AS},
};

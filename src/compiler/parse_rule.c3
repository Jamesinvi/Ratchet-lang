module compiler;
import common;

alias ParseFn = fn ValueType(Compiler* compiler, bool canAssign);

enum Precedence 
{
    NONE,
    ASSIGNMENT, // =
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


struct CompileRule
{
    ParseFn prefix;
    ParseFn infix;
    Precedence precedence;
}


fn CompileRule* get_rule(TokenType operator){
    return &rules[(usz)operator];
}
CompileRule[]rules = {
  [TokenType.LEFT_PAREN.ordinal]    = {&Compiler.grouping,      &Compiler.call,   Precedence.CALL},
  [TokenType.RIGHT_PAREN.ordinal]   = {null,                    null,             Precedence.NONE},
  [TokenType.LEFT_BRACE.ordinal]    = {null,                    null,             Precedence.NONE}, 
  [TokenType.RIGHT_BRACE.ordinal]   = {null,                    null,             Precedence.NONE},
  [TokenType.COMMA.ordinal]         = {null,                    null,             Precedence.NONE},
  [TokenType.DOT.ordinal]           = {null,                    &Compiler.dot,    Precedence.CALL},
  [TokenType.MINUS.ordinal]         = {&Compiler.unary,         &Compiler.binary, Precedence.TERM},
  [TokenType.PLUS.ordinal]          = {null,                    &Compiler.binary, Precedence.TERM},
  [TokenType.SEMICOLON.ordinal]     = {null,                    null,             Precedence.NONE},
  [TokenType.SLASH.ordinal]         = {null,                    &Compiler.binary, Precedence.FACTOR},
  [TokenType.STAR.ordinal]          = {null,                    &Compiler.binary, Precedence.FACTOR},
  [TokenType.BANG.ordinal]          = {&Compiler.unary,          null,            Precedence.NONE},
  [TokenType.BANG_EQUAL.ordinal]    = {null,                    &Compiler.binary, Precedence.EQUALITY},
  [TokenType.EQUAL.ordinal]         = {null,                    null,             Precedence.NONE},
  [TokenType.EQUAL_EQUAL.ordinal]   = {null,                    &Compiler.binary, Precedence.EQUALITY},
  [TokenType.GREATER.ordinal]       = {null,                    &Compiler.binary, Precedence.COMPARISON},
  [TokenType.GREATER_EQUAL.ordinal] = {null,                    &Compiler.binary, Precedence.COMPARISON},
  [TokenType.LESS.ordinal]          = {null,                    &Compiler.binary, Precedence.COMPARISON},
  [TokenType.LESS_EQUAL.ordinal]    = {null,                    &Compiler.binary, Precedence.COMPARISON},
  [TokenType.IDENTIFIER.ordinal]    = {&Compiler.variable,      null,             Precedence.NONE},
  [TokenType.STRING.ordinal]        = {&Compiler.string,        null,             Precedence.NONE},
  [TokenType.INTEGER.ordinal]       = {&Compiler.number,        null,             Precedence.NONE},
  [TokenType.FLOAT.ordinal]         = {&Compiler.number,        null,             Precedence.NONE},
  [TokenType.DOUBLE.ordinal]        = {&Compiler.number,        null,             Precedence.NONE},
  [TokenType.AND.ordinal]           = {null,                    &Compiler.and,    Precedence.AND},
  [TokenType.CLASS.ordinal]         = {null,                    null,             Precedence.NONE},
  [TokenType.ELSE.ordinal]          = {null,                    null,             Precedence.NONE},
  [TokenType.FALSE.ordinal]         = {&Compiler.literal_false, null,             Precedence.NONE},
  [TokenType.FOR.ordinal]           = {null,                    null,             Precedence.NONE},
  [TokenType.FN.ordinal]            = {null,                    null,             Precedence.NONE},
  [TokenType.IF.ordinal]            = {null,                    null,             Precedence.NONE},
  [TokenType.NULL.ordinal]          = {&Compiler.literal_null,  null,             Precedence.NONE},
  [TokenType.OR.ordinal]            = {null,                    &Compiler.or,     Precedence.OR},
  [TokenType.PRINT.ordinal]         = {null,                    null,             Precedence.NONE},
  [TokenType.RETURN.ordinal]        = {null,                    null,             Precedence.NONE},
  [TokenType.SUPER.ordinal]         = {null,                    null,             Precedence.NONE},
  [TokenType.THIS.ordinal]          = {null,                    null,             Precedence.NONE},
  [TokenType.TRUE.ordinal]          = {&Compiler.literal_true,  null,             Precedence.NONE},
  [TokenType.VAR.ordinal]           = {null,                    null,             Precedence.NONE},
  [TokenType.WHILE.ordinal]         = {null,                    null,             Precedence.NONE},
  [TokenType.EOF.ordinal]           = {null,                    null,             Precedence.NONE},
};

module common;


enum OpCode: Byte
{
    RETURN,
    NEGATE_INT,         NEGATE_FLOAT,   NEGATE_DOUBLE,      NEGATE_BOOL,
    ADD_INT,            ADD_FLOAT,      ADD_DOUBLE,
    SUB_INT,            SUB_FLOAT,      SUB_DOUBLE,
    MUL_INT,            MUL_FLOAT,      MUL_DOUBLE,
    DIV_INT,            DIV_FLOAT,      DIV_DOUBLE,
    CONST_NULL,         CONST_TRUE,     CONST_FALSE,
    CONSTANT,
    TO_STRING,
    CONCAT_STRING,
    CAST_F_I,      CAST_D_I, 
    CAST_I_F,      CAST_D_F, 
    CAST_I_D,      CAST_F_D,
    CAST_TO_STRING, 
    GREATER,
    EQUAL,
    LESS,
    NOT,
    ECHO,
    POP,
    DEFINE_GLOBAL,      GET_GLOBAL,     SET_GLOBAL,
    DEFINE_LOCAL,       GET_LOCAL,      SET_LOCAL,
    JMP,                JMP_IF_FALSE,
    LOOP,
    INCREMENT,
    CALL,
}
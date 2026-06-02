module common;
import std::core::mem;
enum ValueType : char
{
    NULL,
    INT,
    FLOAT,
    DOUBLE,
    BOOL,
    STRUCT,
    REF,
    PTR,
}

// For future me: This macro is very simple:
// If i need an int, I read 4 bytes from the array and interpret them as int
// unaligned_load is to tell the compiler this is intentional
macro @as($Type, Byte* bytes){
    return mem::load(($Type*)bytes, $Type::alignment);
}
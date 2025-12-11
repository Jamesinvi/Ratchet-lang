module common;
import std::io;

const NOT_STRUCT = uint.max;

enum ValueType : char
{
    INT,
    FLOAT,
    DOUBLE,
    BOOL,
    NULL,
    STRUCT,
    GC_OBJ,
    NO_GC_OBJ,
}

struct ValueMetadata @packed
{
    char flags;
    char flags2;
    ushort reserved;
    uint typeIndex;     // uint.max is reserved for sentinel value
}


// For future me: This macro is very simple:
// If i need an int, I read 4 bytes from the array and interpret them as int
// unaligned_load is to tell the compiler this is intentional
macro @as($Type, Byte* bytes){
    return @unaligned_load(*($Type*)bytes, $Type.alignof);
}

fn ushort get_type_size(ValueType type)
{
    switch (type) {
        case ValueType.INT:         return int.sizeof;
        case ValueType.FLOAT:       return float.sizeof;
        case ValueType.DOUBLE:      return double.sizeof;
        case ValueType.BOOL:        return bool.sizeof;
        case ValueType.GC_OBJ:      return uptr.sizeof;
        case ValueType.NO_GC_OBJ:   return uptr.sizeof;
        case ValueType.STRUCT:      return uptr.sizeof; // WILL CHANGE TO LOOKUP
        default:                    return 0;
    }
}


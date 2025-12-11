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
    ushort reserved;
    uint typeIndex;     // uint.max is reserved for sentinel value
}


// For future me: These macros are very simple:
// Basically they mean: 
// If i need an int, I read 4 bytes from the array and interpret them as int
// unaligned_load is to tell the compiler this is intentional
macro int @as_int(Byte* bytes){
    return @unaligned_load(*(int*)bytes, int.alignof);
}
macro float @as_float(Byte* bytes){
    return @unaligned_load(*(float*)bytes, float.alignof);
}
macro double @as_double(Byte* bytes){
    return @unaligned_load(*(double*)bytes, double.alignof);
}
macro bool @as_bool(Byte* bytes){
    return @unaligned_load(*(bool*)bytes, bool.alignof);
}
macro Obj* @as_obj(Byte* bytes){
    return @unaligned_load(*(Obj**)bytes, Obj.alignof);
}
macro ObjString* @as_string(Byte* bytes) {     
    return @unaligned_load(*(ObjString**)bytes, ObjString.alignof);
}
macro ObjFunction* @as_func(Byte* bytes) {
    return @unaligned_load(*(ObjFunction**)bytes, ObjFunction.alignof);
}
macro ObjNative* @as_native(Byte* bytes) {
    return @unaligned_load(*(ObjNative**)bytes, ObjNative.alignof);
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


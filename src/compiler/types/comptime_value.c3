module compiler;
import common;
import std::io;

const NOT_STRUCT = uint.max;

struct CompTypeInfo
{
    ValueType type;
    uint structTypeIndex;       // uint.max is reserved for non-structs
    ValueType refToType;        // Will be ValueType.NULL when not it's not a reference
    char flags;
    char flags2;
}


fn ushort get_type_size(CompTypeInfo info)
{
    switch (info.type) {
        case ValueType.INT:         return int.sizeof;
        case ValueType.FLOAT:       return float.sizeof;
        case ValueType.DOUBLE:      return double.sizeof;
        case ValueType.BOOL:        return bool.sizeof;
        case ValueType.GC_OBJ:      nextcase;
        case ValueType.NO_GC_OBJ:   return uptr.sizeof;
        case ValueType.STRUCT:      return structTypes[info.structTypeIndex].sizeInBytes;
        default:                    return 0;
    }
}

fn CompTypeInfo cmptimeinfo_from_value (ValueType type, String name){
    CompTypeInfo result = {};
    result.type = type;
    result.structTypeIndex = uint.max;

    if(type == ValueType.STRUCT){
        result.structTypeIndex = declaredStructs[name]!!;
    }
    return result;
}

fn CompTypeInfo pointee_from_ref(CompTypeInfo r)
{
    CompTypeInfo out = {};
    out.type = r.refToType;
    out.refToType = ValueType.NULL;
    out.structTypeIndex = (out.type == ValueType.STRUCT) ? r.structTypeIndex : uint.max;
    return out;
}

fn bool type_info_matches(CompTypeInfo a, CompTypeInfo b)
{
    if (a.type != b.type) {
        return false;
    }
    if (a.refToType != b.refToType) {
        return false;
    }
    if (a.type == ValueType.STRUCT || a.refToType == ValueType.STRUCT) {
        return a.structTypeIndex == b.structTypeIndex;
    }
    return true;
}

module parser;
import common;
import globals;
import std::io;

const NOT_STRUCT = uint.max;

struct CompTypeInfo
{
    uint structTypeIndex;       // uint.max is reserved for non-structs
    ValueType type;
    ValueType refToType;        // Will be ValueType.NULL when not it's not a reference
}


fn ushort get_type_size(CompTypeInfo info)
{
    switch (info.type) {
        case ValueType.INT:         return int.sizeof;
        case ValueType.FLOAT:       return float.sizeof;
        case ValueType.DOUBLE:      return double.sizeof;
        case ValueType.BOOL:        return bool.sizeof;
        case ValueType.REF:      	nextcase;
        case ValueType.PTR:   		return uptr.sizeof;
        case ValueType.STRUCT:      return globals::structTypes[info.structTypeIndex].sizeInBytes;
        default:                    return 0;
    }
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

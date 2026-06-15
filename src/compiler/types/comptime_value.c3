module compiler;
import common;
import globals;
import std::io;

const NOT_STRUCT = -1;

struct CompTypeInfo
{
    sz structTypeIndex;         // -1 is reserved for non-structs
    ValueType type;
    ValueType refToType;        // Will be ValueType.NULL when not it's not a reference
}


fn ushort get_type_size(CompTypeInfo info)
{
    switch (info.type) {
        case ValueType.INT:         return int::size;
        case ValueType.FLOAT:       return float::size;
        case ValueType.DOUBLE:      return double::size;
        case ValueType.BOOL:        return bool::size;
        case ValueType.REF:      	nextcase;
        case ValueType.PTR:   		return uptr::size;
        case ValueType.STRUCT:      return globals::structTypes[info.structTypeIndex].sizeInBytes;
        default:                    return 0;
    }
}

fn CompTypeInfo pointee_from_ref(CompTypeInfo r)
{
    CompTypeInfo out = {};
    out.type = r.refToType;
    out.refToType = ValueType.NULL;
    out.structTypeIndex = (out.type == ValueType.STRUCT) ? r.structTypeIndex : NOT_STRUCT;
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

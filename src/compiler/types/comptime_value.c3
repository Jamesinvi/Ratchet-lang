module compiler;
import common;
import std::io;

const NOT_STRUCT = uint.max;

struct CompTypeInfo
{
    ValueType type;
    uint structTypeIndex;       // uint.max is reserved for sentinel value
    ushort reserved;
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
        case ValueType.GC_OBJ:      return uptr.sizeof;
        case ValueType.NO_GC_OBJ:   return uptr.sizeof;
        case ValueType.STRUCT:{
            CompStructTypeInfo structInfo = structTypes[info.structTypeIndex];
            // Recursively traverse all fields to get a total size
            ushort total = 0;
            for(int i = 0; i < structInfo.fieldCount; i++){
                total+= get_type_size(structInfo.fieldInfos[i].typeInfo);
            }
            return total;
        }
        default:                    return 0;
    }
}


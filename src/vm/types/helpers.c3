module vm;
import common;

fn ushort get_type_size(ValueType type)
{
    switch (type) {
        case ValueType.INT:         return int.sizeof;
        case ValueType.FLOAT:       return float.sizeof;
        case ValueType.DOUBLE:      return double.sizeof;
        case ValueType.BOOL:        return bool.sizeof;
        case ValueType.GC_OBJ:      return uptr.sizeof;
        case ValueType.NO_GC_OBJ:   return uptr.sizeof;
        default:                    return 0;
    }
}
module vm;
import common;

fn ushort get_type_size(ValueType type)
{
    switch (type) {
        case ValueType.INT:         return int::size;
        case ValueType.FLOAT:       return float::size;
        case ValueType.DOUBLE:      return double::size;
        case ValueType.BOOL:        return bool::size;
        case ValueType.REF:      return uptr::size;
        case ValueType.PTR:   return uptr::size;
        default:                    return 0;
    }
}
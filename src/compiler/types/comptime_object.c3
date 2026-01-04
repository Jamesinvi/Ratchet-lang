module compiler;
import common;
import std::io;
import std::collections::list;
alias NativeFn = fn double();


fn ushort ObjFunction.add_slot(ObjFunction* this, ValueType type, ushort sizeInBytes){
    ushort offset = this.totalLocalsBytes;

    FrameSlotInfo frameSlotInfo = {
        .type = type,
        .sizeInBytes = sizeInBytes,
        .offset = offset,
    };
    ushort index = (ushort)this.slots.len();
    this.slots.push(frameSlotInfo);
    this.totalLocalsBytes += sizeInBytes;

    return index;
}

fn ushort get_obj_pointee_size(CompTypeInfo info)
{
     // It must be a reference for this function to make sense
    assert(is_ref(info));
    if(info.refToType == ValueType.STRUCT){
        return structTypes[info.structTypeIndex].sizeInBytes;
    }
    return get_type_size(cmptimeinfo_from_value(info.refToType, ""));
}

fn bool is_ref(CompTypeInfo info) @inline {
    return info.refToType != ValueType.NULL;
}
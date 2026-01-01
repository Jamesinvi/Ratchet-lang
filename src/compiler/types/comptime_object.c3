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

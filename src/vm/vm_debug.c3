
module vm;
import common;
import log;

fn void Vm.print_disassembly(Vm* this)
{
    log::log("Globals: [");
    foreach (idx, slot : this.frames[0].function.chunk.debugConstantsSlots){
        if(idx>0){
            log::log("|");
        }
        log::log("%s, %s, @%s", ValueType.names[slot.type.ordinal], slot.sizeInBytes, slot.offset);
    }
    log::log("]\n");

    for(int i=0;i<this.frameCount;i++){
        print_function_and_children(this.frames[i].function);
    }
}

fn void print_function_and_children(ObjFunction* function) {
    if(function.name != null){
        log::logn("\n--- Function: %s ---", function.name.str);
    } else {
        log::logn("\n--- Script ---");
    }
    log::log("Locals: [");
    foreach (idx, slot : function.slots) {
        if (idx > 0) log::log(", ");
        log::log("slot %d: %s (%d bytes)", idx, slot.type, slot.sizeInBytes);
    }
    log::log("]\n");
    function.chunk.debug_print();

    // Also descend into function constants
    for (int i = 0; i < (int)function.chunk.debugConstantsSlots.len(); i++) {
        SlotInfo info = function.chunk.debugConstantsSlots[i];
        if (info.type == ValueType.NO_GC_OBJ || info.type == ValueType.GC_OBJ) {
            Byte* constantBytes = &function.chunk.constants[info.offset];
            ObjFunction* child = common::@as(ObjFunction*, constantBytes);
            if (((Obj*)child).type == ObjType.FUNCTION) {
                print_function_and_children(child);
            }
        }
    }
}
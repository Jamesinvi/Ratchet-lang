
module vm;
import common;
import std::io;

fn void Vm.print_stack(Vm* this)
{
    io::printf("stackHead = %d ", this.stackHead);

    if (this.stackHead == 0) {
        io::printf("  <empty>\n");
        return;
    }

    io::printf("  bytes:\n");
    for (int i = 0; i < this.stackHead; i++) {
        io::printf("%02x ", (char)this.stack[i]);
    }
    io::printf("\n");

}

fn void Vm.print_disassembly(Vm* this)
{
    io::printf("Globals: [");
    foreach (idx, slot : this.frames[0].function.chunk.debugConstantsSlots){
        if(idx>0){
            io::printf("|");
        }
        io::printf("%s, %s, @%s", ValueType.names[slot.type.ordinal], slot.sizeInBytes, slot.offset);
    }
    io::printf("]\n");

    for(int i=0;i<this.frameCount;i++){
        print_function_and_children(this.frames[i].function);
    }
}

fn void print_function_and_children(ObjFunction* function) {
    if(function.name != null){
        io::printfn("\n--- Function: %s ---", function.name.str);
    } else {
        io::printfn("\n--- Script ---");
    }
    io::printf("Locals: [");
    foreach (idx, slot : function.slots) {
        if (idx > 0) io::printf(", ");
        io::printf("slot %d: %s (%d bytes)", idx, ValueType.names[slot.type.ordinal], slot.sizeInBytes);
    }
    io::printf("]\n");
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
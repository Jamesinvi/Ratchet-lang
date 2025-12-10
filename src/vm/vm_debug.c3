
module vm;
import common;
import std::io;

fn void Vm.print_stack(Vm* this)
{
    io::printf("Stack |");
    int counter = 0;

    Value* begin = (Value*)&this.stack.items[0];
    Value* end   = (Value*)&this.stack.items[this.stack.size];

    for (Value* slot = begin; slot < end; slot++){
        io::printf("[ ");
        slot.debug_print();
        io::printf(" ]");
        counter++;
    }

    if (counter > 0) {
        io::printf("<---Top\n");
    } else {
        io::printf("\n");
    }
}

fn void Vm.print_disassembly(Vm* this)
{
    for(int i=0;i<this.frameCount;i++){
        io::printfn("function : '%s'", this.frames[i].function.name.str);
        print_function_and_children(this.frames[i].function);
    }
}

fn void print_function_and_children(ObjFunction* function) {
    if(function.name!=null){
        io::printfn("function : '%s'", function.name.str);
    }
    io::printf("Locals: [");
    foreach (idx, slot : function.slots){
        if(idx>0){
            io::printf("|");
        }
        io::printf("%s, %s, @%s", ValueType.names[slot.type.ordinal], slot.sizeInBytes, slot.offset);
    }
    io::printf("]\n");
    function.chunk.debug_print();

    // Also descend into function constants
    for (int i = 0; i < (int)function.chunk.constants.len(); i++) {
        Value* v = &function.chunk.constants[i];
        if (v.type == ValueType.NO_GC_OBJ || v.type == ValueType.GC_OBJ) {
            Obj* o = v.as.objRef;
            if (o.type == ObjType.FUNCTION) {
                ObjFunction* child = (ObjFunction*)o;
                print_function_and_children(child);
            }
        }
    }
}
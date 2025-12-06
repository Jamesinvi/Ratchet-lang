module common;
import std::io;
enum ObjType
{
    STRING,
}

struct Obj (DebugPrintable)
{
    ObjType type;
    ulong allocIndex;
    int refCounter;
    bool isConstant;
}

struct ObjString
{
    Obj obj;
    String str;
}

fn ObjString* create_obj_string(String source, bool isConstant){
    ObjString* object = mem::new(ObjString);

    object.obj.type = ObjType.STRING;
    object.str = String.copy(source, mem);
    object.obj.allocIndex = ulong.max;
    object.obj.refCounter = 0;
    object.obj.isConstant=isConstant;
    return object;
}

fn void Obj.debug_print(Obj* this) @dynamic {
    io::printf("%s, ", ObjType.names[this.type.ordinal]);
    if(this.allocIndex < ulong.max){
        io::printf("%d", this.allocIndex);
    }else{
        io::printf("untracked");
    }
    switch(this.type){
        case ObjType.STRING: io::printf(" %s", ((ObjString*)this).str);
        default: break;
    }
    if (!this.isConstant && this.refCounter == 0){
        io::printf("         <------- safe to GC");
    }
    io::printf("\n");
}
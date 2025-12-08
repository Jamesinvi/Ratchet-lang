module common;
import std::io;
enum ObjType
{
    STRING,
    FUNCTION,
}

enum FunctionType : char
{
    FUNCTION,
    SCRIPT,
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

struct ObjFunction
{
    Obj obj;
    ObjString* name;
    ushort arity;
    Chunk chunk;
}

fn ObjFunction* create_obj_function(String name, bool isConstant){
    ObjFunction* object = mem::new(ObjFunction);
    ObjString* stringObj = create_obj_string(name, isConstant);
    object.obj.allocIndex = ulong.max;
    object.obj.type = ObjType.FUNCTION;
    object.name = stringObj;
    object.chunk.init();
    return object;
}

fn ObjString* create_obj_string(String source, bool isConstant){
    ObjString* object = mem::new(ObjString);

    object.obj.type = ObjType.STRING;
    object.str = String.copy(source, mem);
    object.obj.allocIndex = ulong.max;
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
        case ObjType.FUNCTION: io::printf(" %s", ((ObjFunction*)this).name.str);
        default: break;
    }
    if (!this.isConstant && this.refCounter == 0){
        io::printf("         <------- safe to GC");
    }
    io::printf("\n");
}
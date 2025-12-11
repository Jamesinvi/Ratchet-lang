module common;
import std::io;
import std::collections::list;
enum ObjType : Byte
{
    STRING,
    FUNCTION,
    NATIVE_FUNCTION
}

enum FunctionType : char
{
    FUNCTION,
    SCRIPT,
}
struct Obj (DebugPrintable)  @align(16)
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

    List{SlotInfo} slots;
    ushort totalLocalsBytes;
}

struct SlotInfo
{
    ValueType type;
    ushort sizeInBytes;
    ushort offset;      // Byte offset from frame start
    ushort index;       // slot index in the table
}
alias NativeFn = fn double();
struct ObjNative
{
    Obj obj;
    NativeFn function;
}

fn ObjFunction* create_obj_function(String name, bool isConstant){
    ObjFunction* object = mem::new(ObjFunction);
    ObjString* stringObj = create_obj_string(name, isConstant);
    object.obj.allocIndex = ulong.max;
    object.obj.type = ObjType.FUNCTION;
    object.name = stringObj;
    object.chunk.init();
    object.slots.init(mem);
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

fn ObjNative* create_obj_native(NativeFn function){
    ObjNative* object = mem::new(ObjNative);

    object.obj.type = ObjType.NATIVE_FUNCTION;
    object.obj.isConstant=true;
    object.function = function;
    return object;
}

fn ushort ObjFunction.add_slot(ObjFunction* this, ValueType type){
    ushort size = get_type_size(type);
    ushort offset = this.totalLocalsBytes;

    SlotInfo slotInfo = {
        .type = type,
        .sizeInBytes = size,
        .offset = offset,
    };
    ushort index = (ushort)this.slots.len();
    this.slots.push(slotInfo);
    this.totalLocalsBytes += size;

    return index;
}

fn void Obj.debug_print(Obj* this) @dynamic {
    io::printf("%s, ", ObjType.names[this.type.ordinal]);
    if(this.allocIndex < ulong.max){
        io::printf("%d", this.allocIndex);
    }else{
        io::printf("untracked");
    }
    switch(this.type){
        case ObjType.STRING: io::printf(" '%s', refs:%2d", ((ObjString*)this).str, this.refCounter);
        case ObjType.FUNCTION: io::printf(" '%s', refs:%2d", ((ObjFunction*)this).name.str, this.refCounter);
        case ObjType.NATIVE_FUNCTION: io::printf(" <native fn>");
        default: break;
    }
    if (!this.isConstant && this.refCounter == 0){
        io::printf("<------- safe to GC");
    }
    io::printf("\n");
}
module common;
import std::io;
import std::collections::list;

alias NativeFn = fn double();

// -------- ENUMS -----------

enum ObjType : Byte
{
    STRING,
    REF,
    FUNCTION,
    NATIVE_FUNCTION,
}

// -------- STRUCTS -----------

struct Obj @align(16)
{
    ObjType type;
    bool isConstant;
    int refCounter;
    ulong allocIndex;
}

struct ObjString
{
    Obj obj;
    String str;
}

struct ObjRef
{
    Obj obj;
    ushort sizeInBytes;
    ValueType refTo;
    void* data;
}

struct ObjFunction
{
    Obj obj;
    ValueType returnType;
    ushort arity;
    ushort argsSizeInBytes;
    ushort totalLocalsBytes;
    ushort returnTypeSize;
    Chunk chunk;
    List{FrameSlotInfo} slots;
    ObjString* name;
}

struct ObjNative
{
    Obj obj;
    NativeFn function;
}


struct FrameSlotInfo
{
    ValueType type;
    ushort sizeInBytes;
    ushort offset;      // Byte offset from frame start
    ushort index;       // slot index in the table
}

// -------- Functions/Methods -----------

fn void ObjFunction.deinit(ObjFunction* this){
    this.name.str.free(mem);
    free(this.name);
    this.chunk.deinit();
    this.slots.free();
}


fn ObjFunction* create_obj_function(String name, bool isConstant, ValueType returnType, ushort returnSize){
    ObjFunction* object = mem::new(ObjFunction);
    ObjString* stringObj = create_obj_string(name, isConstant);
    object.returnType = returnType;
    object.returnTypeSize = returnSize;
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


fn ObjRef* create_obj_ref(bool isConstant, ValueType refTo, ushort sizeInBytes, void* data){
    ObjRef* object = mem::new(ObjRef);

    Obj obj;
    object.obj.type = ObjType.REF;
    object.sizeInBytes =  sizeInBytes;
    object.refTo = refTo;
    object.data = data;
    object.obj.allocIndex = ulong.max;
    object.obj.isConstant=isConstant;
    return object;
}


fn ObjNative* create_obj_native(NativeFn* function){
    ObjNative* object = mem::new(ObjNative);

    object.obj.type = ObjType.NATIVE_FUNCTION;
    object.obj.isConstant=true;
    object.function = *function;
    return object;
}

fn void Obj.debug_print(Obj* this) {
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
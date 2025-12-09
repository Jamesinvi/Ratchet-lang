module common;
import std::io;

const NOT_STRUCT = uint.max;

enum ValueType : char
{
    INT,
    FLOAT,
    DOUBLE,
    BOOL,
    NULL,
    STRUCT,
    GC_OBJ,
    NO_GC_OBJ,
}

struct ValueMetadata @packed
{
    char flags;
    ushort reserved;
    uint typeIndex;     // uint.max is reserved for sentinel value
}

struct Value (DebugPrintable) @align(16)
{
    ValueType type;         // 1 byte
    ValueMetadata metadata; // 7 bytes (marked as packed)
    union as                // 8 bytes
    {
        int intNum;
        float floatNum;
        double doubleNum;
        bool boolean;
        Obj* objRef;
    }

}

fn Value make_int(int v) @inline {
    Value x = {};
    x.metadata.typeIndex = NOT_STRUCT;
    x.type = ValueType.INT;
    x.as.intNum = v;
    return x;
}


fn Value make_float(float v) @inline {
    Value x = {};
    x.metadata.typeIndex = NOT_STRUCT;
    x.type = ValueType.FLOAT;
    x.as.floatNum = v;
    return x;
}


fn Value make_double(double v) @inline {
    Value x = {};
    x.metadata.typeIndex = NOT_STRUCT;
    x.type = ValueType.DOUBLE;
    x.as.doubleNum = v;
    return x;
}

fn Value make_string(String str, bool isConstant) @inline {
    ObjString* string = common::create_obj_string(str,isConstant);
    Value v = {};
    v.metadata.typeIndex = NOT_STRUCT;
    v.type = ValueType.GC_OBJ;
    v.as.objRef = &string.obj;
    return v;
}

fn Value make_function(String name, bool isConstant) @inline {
    ObjFunction* func = common::create_obj_function(name, isConstant);
    Value v = {};
    v.metadata.typeIndex = NOT_STRUCT;
    v.type = ValueType.NO_GC_OBJ;
    v.as.objRef = &func.obj;
    return v;
}

fn Value make_native(NativeFn function) @inline {
    ObjNative* native = common::create_obj_native(function);
    Value v = {};
    v.metadata.typeIndex = NOT_STRUCT;
    v.type = ValueType.NO_GC_OBJ;
    v.as.objRef = &native.obj;
    return v;
}

fn void Value.debug_print(Value* v) @dynamic{
    switch(v.type){
        case ValueType.INT:         io::printf("%s", v.as.intNum);  
        case ValueType.FLOAT:       io::printf("%s", v.as.floatNum);  
        case ValueType.DOUBLE:      io::printf("%s", v.as.doubleNum);  
        case ValueType.BOOL:        io::printf("%s", v.as.boolean);  
        case ValueType.STRUCT:      io::printf("struct, change to print");
        case ValueType.NULL:        io::printf("NULL");
        case ValueType.GC_OBJ:      nextcase;
        case ValueType.NO_GC_OBJ:   {
            switch (v.as.objRef.type)
            {
                case ObjType.STRING: io::printf("\"%s\"", @as_string(v).str);
                case ObjType.FUNCTION: io::printf("fn %s", @as_func(v).name.str);
                case ObjType.NATIVE_FUNCTION: io::printf("<native_fn>");
            }
        }
    }
}

macro ObjString* @as_string(Value* v) {
    ObjString* casted = (ObjString*)v.as.objRef;
    return casted;
}

macro ObjFunction* @as_func(Value* v) {
    ObjFunction* casted = (ObjFunction*) v.as.objRef;
    return casted;
}

macro ObjNative* @as_native(Value* v) {
    ObjNative* casted = (ObjNative*) v.as.objRef;
    return casted;
}

fn Obj* Value.get_obj(Value* this){
    Obj* casted = (Obj*)this.as.objRef;
    return casted;
}

fn String value_to_string(Value* v){
    switch(v.type)
    {
        case ValueType.INT:         return string::format(mem, "%s", v.as.intNum);  
        case ValueType.FLOAT:       return string::format(mem, "%s", v.as.floatNum);  
        case ValueType.DOUBLE:      return string::format(mem, "%s", v.as.doubleNum);  
        case ValueType.BOOL:        return string::format(mem, "%s", v.as.boolean);  
        case ValueType.STRUCT:      return string::format(mem, "%s","struct, change to print");
        case ValueType.NULL:        return string::format(mem, "NULL");
        case ValueType.GC_OBJ:      nextcase;
        case ValueType.NO_GC_OBJ:   {
            switch (v.as.objRef.type)
            {
                case ObjType.STRING:            return string::format(mem, "%s", @as_string(v).str);
                case ObjType.FUNCTION:          return string::format(mem, "%s", @as_func(v).name.str);
                case ObjType.NATIVE_FUNCTION:   return string::format(mem, "<native_fn>");
            }
        }
    }
}

fn void print_value(Value v){
    switch(v.type)
    {
        case ValueType.INT:         io::printfn("%s", v.as.intNum);  
        case ValueType.FLOAT:       io::printfn("%s", v.as.floatNum);  
        case ValueType.DOUBLE:      io::printfn("%s", v.as.doubleNum);  
        case ValueType.BOOL:        io::printfn("%s", v.as.boolean);  
        case ValueType.STRUCT:      io::printfn("struct, change to print");
        case ValueType.NULL:        io::printfn("NULL");
        case ValueType.GC_OBJ:      nextcase;
        case ValueType.NO_GC_OBJ:   {
            switch (v.as.objRef.type)
            {
                case ObjType.STRING: io::printfn("%s", @as_string(&v).str);
                case ObjType.FUNCTION: io::printfn("%s", @as_func(&v).name.str);
                case ObjType.NATIVE_FUNCTION: io::printfn("<native_fn>");
            }
        }
    }
}

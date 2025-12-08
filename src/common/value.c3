module common;
import std::io;

enum ValueType : char
{
    INT,
    FLOAT,
    DOUBLE,
    BOOL,
    NULL,
    GC_OBJ,
    NO_GC_OBJ,
}

struct Value (DebugPrintable)
{
    ValueType type;
    union as
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
    x.type = ValueType.INT;
    x.as.intNum = v;
    return x;
}


fn Value make_float(float v) @inline {
    Value x = {};
    x.type = ValueType.FLOAT;
    x.as.floatNum = v;
    return x;
}


fn Value make_double(double v) @inline {
    Value x = {};
    x.type = ValueType.DOUBLE;
    x.as.doubleNum = v;
    return x;
}

fn Value make_string(String str, bool isConstant) @inline {
    ObjString* string = common::create_obj_string(str,isConstant);
    Value v = {};
    v.type = ValueType.GC_OBJ;
    v.as.objRef = &string.obj;
    return v;
}

fn Value make_function(String name, bool isConstant) @inline {
    ObjFunction* string = common::create_obj_function(name, isConstant);
    Value v = {};
    v.type = ValueType.NO_GC_OBJ;
    v.as.objRef = &string.obj;
    return v;
}



fn void Value.debug_print(Value* v) @dynamic{
    switch(v.type){
        case ValueType.INT:         io::printf("%s", v.as.intNum);  
        case ValueType.FLOAT:       io::printf("%s", v.as.floatNum);  
        case ValueType.DOUBLE:      io::printf("%s", v.as.doubleNum);  
        case ValueType.BOOL:        io::printf("%s", v.as.boolean);  
        case ValueType.NULL:        io::printf("NULL");
        case ValueType.GC_OBJ:      nextcase;
        case ValueType.NO_GC_OBJ:   {
            switch (v.as.objRef.type)
            {
                case ObjType.STRING: io::printf("fn %s", @as_string(v).str);
                case ObjType.FUNCTION: io::printf("fn %s", @as_func(v).name.str);
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

fn Obj* Value.get_obj(Value* this){
    Obj* casted = (Obj*)this.as.objRef;
    return casted;
}

fn void print_value(Value v){
    switch(v.type)
    {
        case ValueType.INT:         io::printfn("%s", v.as.intNum);  
        case ValueType.FLOAT:       io::printfn("%s", v.as.floatNum);  
        case ValueType.DOUBLE:      io::printfn("%s", v.as.doubleNum);  
        case ValueType.BOOL:        io::printfn("%s", v.as.boolean);  
        case ValueType.NULL:        io::printfn("NULL");
        case ValueType.GC_OBJ:      nextcase;
        case ValueType.NO_GC_OBJ:   {
            switch (v.as.objRef.type)
            {
                case ObjType.STRING: io::printfn("%s", @as_string(&v).str);
                case ObjType.FUNCTION: io::printfn("%s", @as_func(&v).name.str);
            }
        }
    }
}

module compiler;
import common;

struct ScopeTracker
{
    Local[Byte.max] locals;
    int localCount;
    int scopeDepth;
    ushort nextSlot;
    ValueType returnType;
    ScopeTracker* enclosing;
    ObjFunction* function;
}

fn void ScopeTracker.init(ScopeTracker* this, Compiler* c, ValueType returnType, String name){
    this.scopeDepth = 0;
    this.localCount = 0;
    this.returnType = returnType;
    this.function   = common::create_obj_function(name, false);
    this.nextSlot  = 0;

    // Dummy local 0 for this function
    Local* local = &this.locals[this.localCount++];
    local.depth      = 0;
    local.name.value = "";

}
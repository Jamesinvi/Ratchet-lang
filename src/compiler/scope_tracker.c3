module compiler;
import common;
import debug;

struct ScopeTracker
{
    Local[Byte.max] locals;
    int localCount;
    int depth;
    ushort nextSlot;
    CompTypeInfo returnTypeInfo;
    ScopeTracker* enclosing;
    ObjFunction* function;
}

fn void ScopeTracker.init(ScopeTracker* this, Compiler* c, CompTypeInfo returnTypeInfo, String name){
    debug::@log_compilation("initializing new scope for function %s", name);
    this.depth = 0;
    this.localCount = 0;
    this.returnTypeInfo = returnTypeInfo;
    this.function   = common::create_obj_function(name, false, returnTypeInfo.type, get_type_size(returnTypeInfo));
    this.nextSlot  = 0;

    // Dummy local 0 for this function
    Local* local = &this.locals[this.localCount++];
    local.depth      = 0;
    local.name.value = "";

}
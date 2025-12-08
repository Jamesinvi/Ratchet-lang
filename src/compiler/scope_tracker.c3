module compiler;
import common;

struct ScopeTracker
{
    ScopeTracker* enclosing;
    ObjFunction* function;
    ValueType returnType;
    Local[Byte.max] locals;
    int localCount;
    int scopeDepth;
}

fn void ScopeTracker.init(ScopeTracker* this, Compiler* c, ValueType returnType, String name){
    this.scopeDepth = 0;
    this.localCount = 0;
    this.returnType = returnType;
    this.enclosing  = c.currentScope;
    this.function   = common::create_obj_function(name, false);

    // Dummy local 0 for this function
    Local* local = &this.locals[this.localCount++];
    local.depth      = 0;
    local.name.value = "";

    // Now install this tracker in the compiler
    c.currentScope = this;
}
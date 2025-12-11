module vm;
import common;
import std::collections::list;
import std::collections::map;
import debug;
import std::io;
alias Chunk = common::Chunk;
alias Byte = char;

const FRAMES_MAX = 64;
const STACK_MAX = (FRAMES_MAX * Byte.max);

enum RunResult
{
    OK,
    RUNTIME_ERR,
}

struct Vm
{
    Byte[STACK_MAX] stack;
    ushort stackHead;

    CallFrame* frame;
    CallFrame[FRAMES_MAX] frames;
    int frameCount;

    HeapTracker trackedHeap;
    HeapTracker untrackedHeap;
    HashMap{String, Obj*} globals;
}

fn void Vm.init(Vm* this, ObjFunction* entryPoint){
    this.stackHead = 0;
    this.frameCount = 0;
    this.trackedHeap.init("TRACKED HEAP");
    this.untrackedHeap.init("UNTRACKED HEAP");
    this.globals.init(mem);

    this.frame = &this.frames[this.frameCount++];
    this.frame.function = entryPoint;
    this.frame.ip = (Byte*)&entryPoint.chunk.code[0];
    this.frame.base = 0;
    this.stackHead = entryPoint.totalLocalsBytes;


    this.define_native("clock", &clock_native);
}

fn void Vm.deinit(Vm* this){
    this.trackedHeap.free();
    this.untrackedHeap.free();
    this.globals.free();
}
macro Byte @read_u8(Vm* vm){
    return *vm.frame.ip++;
}

macro ushort @read_u16(Vm* vm){
    ushort hi = (ushort)vm.frame.ip[0];
    ushort lo = (ushort)vm.frame.ip[1];
    vm.frame.ip += 2;
    return (ushort)((hi << 8) | lo);
}

macro @read_const(Vm* vm, $Type, ushort offset) {
    Byte* bytes = &vm.frame.function.chunk.constants[offset];
    return @unaligned_load(*($Type*)bytes, $Type.alignof);
}

const OP_LESS = 0;
const OP_GREATER = 1;
const OP_EQUAL = 2;
const OP_ADD = 3;
const OP_SUB = 4;
const OP_MUL = 5;
const OP_DIV = 6;
const OP_NEGATE = 7;

macro @compare(Vm* vm, $Type, $op){
    $Type right = @pop_val(vm, $Type);
    $Type left = @pop_val(vm, $Type);
    $switch $op:
        $case OP_LESS:       @push_bool(vm, left < right);
        $case OP_GREATER:    @push_bool(vm, left > right);
        $case OP_EQUAL:      @push_bool(vm, left == right);
    $endswitch
}




macro @math_int(Vm* vm, $op){
    int right = @pop_val(vm, int);
    int left = @pop_val(vm, int);
    $switch $op:
        $case OP_ADD:       @push_int(vm, left + right);
        $case OP_SUB:       @push_int(vm, left - right);
        $case OP_MUL:       @push_int(vm, left * right);
        $case OP_DIV:{
            if (right == 0) {
                vm.error("Division by zero");
            }
            @push_int(vm, left / right);
        }
    $endswitch
}

macro @math_float(Vm* vm, $op){
    float right = @pop_val(vm, float);
    float left = @pop_val(vm, float);
    $switch $op:
        $case OP_ADD:       @push_float(vm, left + right);
        $case OP_SUB:       @push_float(vm, left - right);
        $case OP_MUL:       @push_float(vm, left * right);
        $case OP_DIV:{
            if (right == 0f) {
                vm.error("Division by zero");
            }
            @push_float(vm, left / right);
        }
    $endswitch
}


macro @math_double(Vm* vm, $op){
    double right = @pop_val(vm, double);
    double left = @pop_val(vm, double);
    $switch $op:
        $case OP_ADD:       @push_double(vm, left + right);
        $case OP_SUB:       @push_double(vm, left - right);
        $case OP_MUL:       @push_double(vm, left * right);
        $case OP_DIV:{
            if (right == 0f) {
                vm.error("Division by zero");
            }
            @push_double(vm, left / right);
        }
    $endswitch
}

macro @negate_int(Vm* vm){
    int right = @pop_val(vm, int);
    @push_int(vm, -right);
}

macro @negate_float(Vm* vm){
    float right = @pop_val(vm, float);
    @push_float(vm, -right);
}

macro @negate_double(Vm* vm){
    double right = @pop_val(vm, double);
    @push_double(vm, -right);
}


macro @read_local(Vm* vm, $Type, ushort offset) {
    Byte* bytes = &vm.stack[offset];
    return @unaligned_load(*($Type*)bytes, $Type.alignof);
}

macro @peek_val(Vm* vm, $Type){
    Byte* src = &vm.stack[vm.stackHead - $Type.sizeof];
    return @unaligned_load(*($Type*)src, $Type.alignof);
}

macro @pop_val(Vm* vm, $Type) {
    vm.stackHead -= $Type.sizeof;
    Byte* src = &vm.stack[vm.stackHead];
    return @unaligned_load(*($Type*)src, $Type.alignof);
}

macro void @push_int(Vm* vm, int value) {
    Byte* dst = &vm.stack[vm.stackHead];
    @unaligned_store(*(int*)dst, value, int.alignof);
    vm.stackHead += int.sizeof;
}

macro void @push_float(Vm* vm, float value) {
    Byte* dst = &vm.stack[vm.stackHead];
    @unaligned_store(*(float*)dst, value, float.alignof);
    vm.stackHead += float.sizeof;
}

macro void @push_double(Vm* vm, double value) {
    Byte* dst = &vm.stack[vm.stackHead];
    @unaligned_store(*(double*)dst, value, double.alignof);
    vm.stackHead += double.sizeof;
}

macro void @push_bool(Vm* vm, bool value) {
    Byte* dst = &vm.stack[vm.stackHead];
    @unaligned_store(*(bool*)dst, value, bool.alignof);
    vm.stackHead += bool.sizeof;

}

macro void @push_obj(Vm* vm, Obj* obj) {
    Byte* dst = &vm.stack[vm.stackHead];
    @unaligned_store(*(Obj**)dst, obj, uptr.alignof);
    vm.stackHead += uptr.sizeof;
}

macro void @push_func(Vm* vm, ObjFunction* func) {
    Byte* dst = &vm.stack[vm.stackHead];
    @unaligned_store(*(ObjFunction**)dst, func, uptr.alignof);
    vm.stackHead += uptr.sizeof;
}

macro void @push_string(Vm* vm, ObjString* str) {
    Byte* dst = &vm.stack[vm.stackHead];
    @unaligned_store(*(ObjString**)dst, str, uptr.alignof);
    vm.stackHead += uptr.sizeof;
}


fn RunResult run(Vm* vm) {
    debug::@print_disassembly(vm);

    while (true) {
        Byte instruction = @read_u8(vm);  
        //io::printfn("%s", vm.stackHead);  
        debug::@print_instruction(vm);
        switch (instruction) {

            // ---------- Constants ----------

            case OpCode.CONST_INT.ordinal: {
                ushort offset = @read_u16(vm);
                int v = @read_const(vm, int, offset);
                @push_int(vm, v);
            }

            case OpCode.CONST_FLOAT.ordinal: {
                ushort offset = @read_u16(vm);
                float v = @read_const(vm, float, offset);
                @push_float(vm, v);
            }

            case OpCode.CONST_DOUBLE.ordinal: {
                ushort offset = @read_u16(vm);
                double v = @read_const(vm, double, offset);
                @push_double(vm, v);
            }

            case OpCode.CONST_FUNC.ordinal: {
                ushort offset = @read_u16(vm);
                ObjFunction* func = @read_const(vm, ObjFunction*, offset);
                @push_func(vm, func);
            }

            case OpCode.CONST_TRUE.ordinal: {
                @push_bool(vm,  true);
            }

            case OpCode.CONST_FALSE.ordinal: {
                @push_bool(vm,  false);
            }

            case OpCode.CONST_NULL.ordinal: {
                @push_bool(vm,  false);
            }

            // ---------- Locals ----------

            case OpCode.GET_LOCAL.ordinal: {
                ushort slotIndex = @read_u16(vm);
                SlotInfo info = vm.frame.function.slots[slotIndex];
                ushort offset = vm.frame.base + info.offset;

                switch (info.type) {
                    case ValueType.INT: {
                        int v = @read_local(vm, int, offset);
                        @push_int(vm, v);
                    }

                    case ValueType.FLOAT: {
                        float v = @read_local(vm, float, offset);
                        @push_float(vm, v);
                    }

                    case ValueType.DOUBLE: {
                        double v = @read_local(vm, double, offset);
                        @push_double(vm, v);
                    }

                    case ValueType.BOOL: {
                        bool v = @read_local(vm, bool, offset);
                        @push_bool(vm, v);
                    }

                    case ValueType.GC_OBJ:
                    case ValueType.NO_GC_OBJ: {
                        Obj* v = @read_local(vm, Obj*, offset);
                        @push_obj(vm, v);
                    }
                    case ValueType.NULL: {
                        @push_bool(vm, false); // or special NULL handling
                    }

                    default:
                        vm.error("Unsupported local type in GET_LOCAL");
                        return RunResult.RUNTIME_ERR;
                }
            }

            case OpCode.SET_LOCAL.ordinal: {
                ushort slotIndex = @read_u16(vm);
                SlotInfo info = vm.frame.function.slots[slotIndex];
                ushort offset = vm.frame.base + info.offset;

                vm.stackHead -= info.sizeInBytes;
                for (int i = 0; i < info.sizeInBytes; i++) {
                    vm.stack[offset + i] = vm.stack[vm.stackHead + i];
                }
            }

            // ---------- Globals: function-only ----------

            case OpCode.DEFINE_GLOBAL.ordinal: {
                // const: string name
                ushort nameOffset = @read_u16(vm);
                ObjString* nameObj = @read_const(vm, ObjString*, nameOffset);
                String name = nameObj.str;

                Obj* obj = @pop_val(vm, Obj*);
                vm.globals.set(name, obj);
            }

            case OpCode.GET_GLOBAL.ordinal: {
                ushort nameOffset = @read_u16(vm);
                ObjString* nameObj = @read_const(vm, ObjString*, nameOffset);
                String name = nameObj.str;

                Obj*? maybeObj = vm.globals.get(name);
                if (catch err = maybeObj) {
                    vm.error("Undefined global");
                    return RunResult.RUNTIME_ERR;
                }
                @push_obj(vm, maybeObj);
            }

            // ---------- Control flow -----------------
            
            case OpCode.JMP.ordinal: {
                ushort offset = @read_u16(vm);
                vm.frame.ip += offset;
            }
            
            case OpCode.JMP_IF_FALSE.ordinal: {
                ushort offset = @read_u16(vm);
                // Compiler keeps the condition on the stack and POPs it later,
                // so we just peek it here.
                if (!@peek_val(vm, bool)) {
                    vm.frame.ip += offset;
                }
            }

            case OpCode.LOOP.ordinal: {
                ushort offset = @read_u16(vm);
                vm.frame.ip -= offset;
            }

            // ----------- Casts ---------------------

            case OpCode.CAST_TO_STRING.ordinal: {
                ValueType fromType = (ValueType)@read_u8(vm);
                String s;
                switch (fromType) {
                    case ValueType.INT:         s = string::format(mem, "%d", @pop_val(vm, int));
                    case ValueType.FLOAT:       s = string::format(mem, "%f", @pop_val(vm, float));
                    case ValueType.DOUBLE:      s = string::format(mem, "%f", @pop_val(vm, double));
                    case ValueType.BOOL:        s = string::format(mem, "%b", @pop_val(vm, bool));
                    case ValueType.NULL:        s = "null"; @pop_val(vm, bool);
                    default:{
                        vm.error("Unsupported cast"); 
                        return RunResult.RUNTIME_ERR;
                    }
                }
                ObjString* result = common::create_obj_string(s, false);
                @push_string(vm, result);
                vm.trackedHeap.track_alloc((Obj*)result);
            }

            // ---------- Comparison -----------------

            case OpCode.INT_LESS.ordinal:           @compare(vm, int, OP_LESS);
            case OpCode.INT_GREATER.ordinal:        @compare(vm, int, OP_GREATER);
            case OpCode.INT_EQUAL.ordinal:          @compare(vm, int, OP_EQUAL);
            
            case OpCode.FLOAT_LESS.ordinal:         @compare(vm, float, OP_LESS);
            case OpCode.FLOAT_GREATER.ordinal:      @compare(vm, float, OP_GREATER);
            case OpCode.FLOAT_EQUAL.ordinal:        @compare(vm, float, OP_EQUAL);

            case OpCode.DOUBLE_LESS.ordinal:        @compare(vm, double, OP_LESS);
            case OpCode.DOUBLE_GREATER.ordinal:     @compare(vm, double, OP_GREATER);
            case OpCode.DOUBLE_EQUAL.ordinal:       @compare(vm, double, OP_EQUAL);

            case OpCode.NOT.ordinal: {
                bool v = @pop_val(vm, bool);
                @push_bool(vm, !v);
            }
            // ---------- Arithmetic ----------


            case OpCode.INC_LOCAL.ordinal: {
                ushort slotIndex = @read_u16(vm);
                SlotInfo info = vm.frame.function.slots[slotIndex];
                ushort offset = vm.frame.base + info.offset;

                // Read current int
                int v = @read_local(vm, int, offset);
                v += 1;

                // Write it back in-place
                Byte* dst = &vm.stack[offset];
                @unaligned_store(*(int*)dst, v, int.alignof);
            }

            case OpCode.ADD_INT.ordinal:            @math_int(vm, OP_ADD);
            case OpCode.SUB_INT.ordinal:            @math_int(vm, OP_SUB);  
            case OpCode.MUL_INT.ordinal:            @math_int(vm, OP_MUL); 
            case OpCode.DIV_INT.ordinal:            @math_int(vm, OP_DIV); 
            case OpCode.NEGATE_INT.ordinal:         @negate_int(vm);


            case OpCode.ADD_FLOAT.ordinal:          @math_float(vm, OP_ADD);
            case OpCode.SUB_FLOAT.ordinal:          @math_float(vm, OP_SUB);  
            case OpCode.MUL_FLOAT.ordinal:          @math_float(vm, OP_MUL); 
            case OpCode.DIV_FLOAT.ordinal:          @math_float(vm, OP_DIV); 
            case OpCode.NEGATE_FLOAT.ordinal:       @negate_float(vm);


            case OpCode.ADD_DOUBLE.ordinal:         @math_double(vm, OP_ADD);
            case OpCode.SUB_DOUBLE.ordinal:         @math_double(vm, OP_SUB);  
            case OpCode.MUL_DOUBLE.ordinal:         @math_double(vm, OP_MUL); 
            case OpCode.DIV_DOUBLE.ordinal:         @math_double(vm, OP_DIV); 
            case OpCode.NEGATE_DOUBLE.ordinal:      @negate_double(vm);

            // ---------- Output ----------

            case OpCode.ECHO.ordinal: {
                double v = @pop_val(vm, double);
                io::printfn("%f", v);
            }

            case OpCode.POP.ordinal: {
                Byte size = @read_u8(vm);
                vm.stackHead -= size;
            }

            // ---------- Call / Return ----------

            case OpCode.CALL.ordinal: {
                Byte argCount = @read_u8(vm);

                ushort funcOffset = (ushort)(vm.stackHead - (argCount * int.sizeof) - uptr.sizeof);
                Obj* callee = @unaligned_load(*(Obj**)&vm.stack[funcOffset], uptr.alignof);

                switch (callee.type) {
                    case ObjType.FUNCTION: {
                        ObjFunction* func = (ObjFunction*)callee;

                        if (vm.frameCount >= FRAMES_MAX) {
                            vm.error("Stack overflow");
                            return RunResult.RUNTIME_ERR;
                        }

                        CallFrame* newFrame = &vm.frames[vm.frameCount++];
                        newFrame.function = func;
                        newFrame.ip = (Byte*)&func.chunk.code[0];
                        newFrame.base = funcOffset;
                        vm.frame = newFrame;

                        vm.stackHead = (ushort)(newFrame.base + func.totalLocalsBytes);
                    }

                    case ObjType.NATIVE_FUNCTION: {
                        ObjNative* nativeFn = (ObjNative*)callee;

                        // Example for 0-arg double native:
                        double result = nativeFn.function();
                        // drop the callee+args from the stack:
                        vm.stackHead = funcOffset;
                        @push_double(vm, result);
                    }

                    default:
                        vm.error("Attempted to call non-callable object");
                        return RunResult.RUNTIME_ERR;
                }
            }


            case OpCode.RETURN.ordinal: {
                vm.frameCount--;
                if (vm.frameCount == 0) {
                    return RunResult.OK;
                }

                vm.stackHead = vm.frame.base;
                vm.frame = &vm.frames[vm.frameCount - 1];
            }

            // ---------- Fallback ----------

            default: {
                vm.error("Unknown opcode");
                return RunResult.RUNTIME_ERR;
            }
        }
        debug::@print_stack(vm);
    }
}


// ========== Error handling ==========

fn void Vm.error(Vm* this, String msg) {
    io::printfn("Runtime error: %s", msg);
    for (int i = this.frameCount - 1; i >= 0; i--) {
        CallFrame* frame = &this.frames[i];
        ObjFunction* function = frame.function;

        int instruction = (int)(frame.ip - &function.chunk.code[0]) - 1;
        if (instruction < 0) instruction = 0;

        io::printf("[line %d] in ", function.chunk.lines[instruction]);
        if (function.name == null) {
            io::printfn("script");
        } else {
            io::printfn("%s()", function.name.str);
        }
    }
}
fn void Vm.define_native(Vm* vm, String name, NativeFn function) {
    ObjNative* nativeFn = common::create_obj_native(function);
    vm.globals.set(name, &nativeFn.obj);
}
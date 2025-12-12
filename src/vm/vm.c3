module vm;
import common;
import std::collections::map;
import debug;
import std::io;
import log;
alias Chunk = common::Chunk;
alias Byte  = char;

const FRAMES_MAX = 64;
const STACK_MAX  = (FRAMES_MAX * Byte.max);

// Helpers for Math operation macros
const OP_LESS    = 0;
const OP_GREATER = 1;
const OP_EQUAL   = 2;
const OP_ADD     = 3;
const OP_SUB     = 4;
const OP_MUL     = 5;
const OP_DIV     = 6;
const OP_NEGATE  = 7;

faultdef RUNTIME_ERROR;

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

fn void Vm.init(Vm* this, ObjFunction* entryPoint)
{
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

fn void Vm.deinit(Vm* this)
{
    this.trackedHeap.free();
    this.untrackedHeap.free();
    foreach(obj : common::allocatedConstants){
        if(obj.type == ObjType.FUNCTION){
            ((ObjFunction*)obj).deinit();
            free(((ObjFunction*)obj));
        }else if (obj.type == ObjType.STRING){
            ((ObjString*)obj).str.free(mem);
            free(((ObjString*)obj));
        }else if (obj.type == ObjType.NATIVE_FUNCTION){
            free(((ObjNative*)obj));
        }
    }
    common::allocatedConstants.free();
    this.globals.free();


}

macro Byte @read_u8(Vm* vm)
{
    return *vm.frame.ip++;
}

macro ushort @read_u16(Vm* vm)
{
    ushort hi = (ushort)vm.frame.ip[0];
    ushort lo = (ushort)vm.frame.ip[1];
    vm.frame.ip += 2;
    return (ushort)((hi << 8) | lo);
}

macro @read_const(Vm* vm, $Type, ushort offset)
{
    Byte* bytes = &vm.frame.function.chunk.constants[offset];
    return common::@as($Type, bytes);
}

macro @read_local(Vm* vm, $Type, ushort offset)
{
    Byte* bytes = &vm.stack[offset];
    return @unaligned_load(*($Type*)bytes, $Type.alignof);
}

macro @read_const_and_push(Vm* vm, $Type){
    ushort offset = @read_u16(vm);
    $Type v = @read_const(vm, $Type, offset);
    @push_val(vm, $Type, v);
}

macro @read_local_and_push(Vm* vm, $Type, ushort offset){
    $Type v = @read_local(vm, $Type, offset);
    @push_val(vm, $Type, v);
}

macro @compare(Vm* vm, $Type, $op)
{
    $Type right = @pop_val(vm, $Type);
    $Type left  = @pop_val(vm, $Type);
    $switch $op:
        $case OP_LESS:    @push_val(vm, bool, left < right);
        $case OP_GREATER: @push_val(vm, bool, left > right);
        $case OP_EQUAL:   @push_val(vm, bool, left == right);
    $endswitch
}

macro @math(Vm* vm, $Type, $op)
{
    $Type right = @pop_val(vm, $Type);
    $Type left  = @pop_val(vm, $Type);

    $switch $op:
        $case OP_ADD: @push_val(vm, $Type, left + right);
        $case OP_SUB: @push_val(vm, $Type, left - right);
        $case OP_MUL: @push_val(vm, $Type, left * right);
        $case OP_DIV:
        {
            if (right == 0) {
                vm.error("Division by zero");
            }
            @push_val(vm, $Type, left / right);
        }
    $endswitch
}

macro @negate(Vm* vm, $Type)
{
    $Type right = @pop_val(vm, $Type);
    @push_val(vm, $Type, -right);
}


macro @peek_val(Vm* vm, $Type)
{
    Byte* src = &vm.stack[vm.stackHead - $Type.sizeof];
    return @unaligned_load(*($Type*)src, $Type.alignof);
}

macro @pop_val(Vm* vm, $Type)
{
    vm.stackHead -= $Type.sizeof;
    Byte* src = &vm.stack[vm.stackHead];
    return @unaligned_load(*($Type*)src, $Type.alignof);


}

macro @push_val(Vm* vm, $Type, value)
{
    Byte* dst = &vm.stack[vm.stackHead];
    @unaligned_store(*($Type*)dst, value, $Type.alignof);
    vm.stackHead += $Type.sizeof;
}

fn RunResult run(Vm* vm)
{
    debug::@print_disassembly(vm);

    while (true) {
        Byte instruction = @read_u8(vm);
        debug::@print_instruction(vm);
        switch (instruction) {

            // ---------- Constants ----------

            case OpCode.CONST_INT.ordinal:      @read_const_and_push(vm, int);
            case OpCode.CONST_FLOAT.ordinal:    @read_const_and_push(vm, float);        
            case OpCode.CONST_DOUBLE.ordinal:   @read_const_and_push(vm, double);
            case OpCode.CONST_FUNC.ordinal:     @read_const_and_push(vm, ObjFunction*);
            case OpCode.CONST_TRUE.ordinal:     @push_val(vm, bool, true);
            case OpCode.CONST_FALSE.ordinal:    @push_val(vm, bool, false);
            case OpCode.CONST_NULL.ordinal:     @push_val(vm, bool, false);

            // ---------- Locals ----------

            case OpCode.GET_LOCAL.ordinal:
            {
                ushort slotIndex = @read_u16(vm);
                SlotInfo info    = vm.frame.function.slots[slotIndex];
                ushort offset    = vm.frame.base + info.offset;
                switch (info.type) {
                    case ValueType.INT:         @read_local_and_push(vm, int, offset);
                    case ValueType.FLOAT:       @read_local_and_push(vm, float, offset);
                    case ValueType.DOUBLE:      @read_local_and_push(vm, double, offset);
                    case ValueType.BOOL:        @read_local_and_push(vm, bool, offset);
                    case ValueType.GC_OBJ:      nextcase;
                    case ValueType.NO_GC_OBJ:   @read_local_and_push(vm, Obj*, offset);
                    case ValueType.NULL:        @push_val(vm, bool, false); // or special NULL handling
                    default:
                        vm.error("Unsupported local type in GET_LOCAL");
                        return RunResult.RUNTIME_ERR;
                }
            }

            case OpCode.SET_LOCAL.ordinal:
            {
                ushort slotIndex = @read_u16(vm);
                SlotInfo info = vm.frame.function.slots[slotIndex];
                ushort offset = vm.frame.base + info.offset;

                vm.stackHead -= info.sizeInBytes;
                for (int i = 0; i < info.sizeInBytes; i++) {
                    vm.stack[offset + i] = vm.stack[vm.stackHead + i];
                }
            }

            // ---------- Globals: function-only ----------

            case OpCode.DEFINE_GLOBAL.ordinal:
            {
                ushort nameOffset = @read_u16(vm);
                ObjString* nameObj = @read_const(vm, ObjString*, nameOffset);
                String name = nameObj.str;

                Obj* obj = @pop_val(vm, Obj*);
                vm.globals.set(name, obj);
            }

            case OpCode.GET_GLOBAL.ordinal:
            {
                ushort nameOffset  = @read_u16(vm);
                ObjString* nameObj = @read_const(vm, ObjString*, nameOffset);
                String name = nameObj.str;

                Obj*? maybeObj = vm.globals.get(name);
                if (catch err = maybeObj) {
                    vm.error("Undefined global");
                    return RunResult.RUNTIME_ERR;
                }
                @push_val(vm, Obj*, maybeObj);
            }

            // ---------- Control flow -----------------

            case OpCode.JMP.ordinal:
            {
                ushort offset = @read_u16(vm);
                vm.frame.ip += offset;
            }

            case OpCode.JMP_IF_FALSE.ordinal:
            {
                ushort offset = @read_u16(vm);
                if (!@peek_val(vm, bool)) {
                    vm.frame.ip += offset;
                }
            }

            case OpCode.LOOP.ordinal:
            {
                ushort offset = @read_u16(vm);
                vm.frame.ip -= offset;
            }

            // ----------- Casts ---------------------

            case OpCode.CAST_TO_STRING.ordinal:
            {
                ValueType fromType = (ValueType)@read_u8(vm);
                String s;

                switch (fromType) {
                    case ValueType.INT:    s = string::format(mem, "%d", @pop_val(vm, int));
                    case ValueType.FLOAT:  s = string::format(mem, "%f", @pop_val(vm, float));
                    case ValueType.DOUBLE: s = string::format(mem, "%f", @pop_val(vm, double));
                    case ValueType.BOOL:   s = string::format(mem, "%b", @pop_val(vm, bool));
                    case ValueType.NULL:   s = "null"; @pop_val(vm, bool);

                    default:
                    {
                        vm.error("Unsupported cast");
                        return RunResult.RUNTIME_ERR;
                    }
                }

                ObjString* result = common::create_obj_string(s, false);
                @push_val(vm, ObjString*, result);
                vm.trackedHeap.track_alloc((Obj*)result);
            }

            // ---------- Comparison -----------------

            case OpCode.INT_LESS.ordinal:        @compare(vm, int,    OP_LESS);
            case OpCode.INT_GREATER.ordinal:     @compare(vm, int,    OP_GREATER);
            case OpCode.INT_EQUAL.ordinal:       @compare(vm, int,    OP_EQUAL);

            case OpCode.FLOAT_LESS.ordinal:      @compare(vm, float,  OP_LESS);
            case OpCode.FLOAT_GREATER.ordinal:   @compare(vm, float,  OP_GREATER);
            case OpCode.FLOAT_EQUAL.ordinal:     @compare(vm, float,  OP_EQUAL);

            case OpCode.DOUBLE_LESS.ordinal:     @compare(vm, double, OP_LESS);
            case OpCode.DOUBLE_GREATER.ordinal:  @compare(vm, double, OP_GREATER);
            case OpCode.DOUBLE_EQUAL.ordinal:    @compare(vm, double, OP_EQUAL);

            case OpCode.NOT.ordinal:
            {
                bool v = @pop_val(vm, bool);
                @push_val(vm, bool, !v);
            }

            // ---------- Arithmetic ----------

            case OpCode.INC_LOCAL.ordinal:
            {
                ushort slotIndex = @read_u16(vm);
                SlotInfo info    = vm.frame.function.slots[slotIndex];
                ushort offset    = vm.frame.base + info.offset;

                int v = @read_local(vm, int, offset);
                v += 1;

                Byte* dst = &vm.stack[offset];
                @unaligned_store(*(int*)dst, v, int.alignof);
            }

            case OpCode.ADD_INT.ordinal:       @math(vm, int,    OP_ADD);
            case OpCode.SUB_INT.ordinal:       @math(vm, int,    OP_SUB);
            case OpCode.MUL_INT.ordinal:       @math(vm, int,    OP_MUL);
            case OpCode.DIV_INT.ordinal:       @math(vm, int,    OP_DIV);
            case OpCode.NEGATE_INT.ordinal:    @negate(vm, int);

            case OpCode.ADD_FLOAT.ordinal:     @math(vm, float,  OP_ADD);
            case OpCode.SUB_FLOAT.ordinal:     @math(vm, float,  OP_SUB);
            case OpCode.MUL_FLOAT.ordinal:     @math(vm, float,  OP_MUL);
            case OpCode.DIV_FLOAT.ordinal:     @math(vm, float,  OP_DIV);
            case OpCode.NEGATE_FLOAT.ordinal:  @negate(vm, float);

            case OpCode.ADD_DOUBLE.ordinal:    @math(vm, double, OP_ADD);
            case OpCode.SUB_DOUBLE.ordinal:    @math(vm, double, OP_SUB);
            case OpCode.MUL_DOUBLE.ordinal:    @math(vm, double, OP_MUL);
            case OpCode.DIV_DOUBLE.ordinal:    @math(vm, double, OP_DIV);
            case OpCode.NEGATE_DOUBLE.ordinal: @negate(vm, double);

            // ---------- Output ----------

            case OpCode.ECHO.ordinal:
            {
                ValueType type = (ValueType)@read_u8(vm);

                switch (type) {
                    case ValueType.INT:         io::printfn("%d", @pop_val(vm, int));
                    case ValueType.FLOAT:       io::printfn("%f", @pop_val(vm, float));
                    case ValueType.DOUBLE:      io::printfn("%f", @pop_val(vm, double));
                    case ValueType.BOOL:        io::printfn("%s", @pop_val(vm, bool));
                    case ValueType.NULL:        io::printfn("null"); @pop_val(vm, bool);
                    case ValueType.STRUCT:      io::printfn("Struct"); @pop_val(vm, int);
                    case ValueType.NO_GC_OBJ:   nextcase;
                    case ValueType.GC_OBJ:
                    {
                        Obj* obj = @pop_val(vm, Obj*);
                        ObjType kind = obj.type;

                        switch (kind) {
                            case ObjType.STRING:            io::printfn("%s", ((ObjString*)obj).str);
                            case ObjType.FUNCTION:          io::printfn("fn: %s", ((ObjFunction*)obj).name.str);
                            case ObjType.NATIVE_FUNCTION:   io::printfn("native fn");
                        }
                    }
                }
            }

            case OpCode.POP.ordinal:
            {
                Byte size = @read_u8(vm);
                vm.stackHead -= size;
            }

            // ---------- Call / Return ----------

            case OpCode.CALL.ordinal:
            {
                Byte argCount = @read_u8(vm);
                ushort argBytesSize = @read_u16(vm);

                ushort funcOffset = (ushort)(vm.stackHead - (ulong)argBytesSize - uptr.sizeof);

                Obj* callee = common::@as(Obj*, &vm.stack[funcOffset]);

                switch (callee.type) {
                    case ObjType.FUNCTION:
                    {
                        ObjFunction* func = (ObjFunction*)callee;

                        if (vm.frameCount >= FRAMES_MAX) {
                            vm.error("Stack overflow");
                            return RunResult.RUNTIME_ERR;
                        }

                        CallFrame* newFrame = &vm.frames[vm.frameCount++];
                        newFrame.function = func;
                        newFrame.ip = (Byte*)&func.chunk.code[0];
                        newFrame.base = funcOffset + uptr.sizeof;
                        newFrame.callee = callee;

                        vm.frame = newFrame;

                        vm.stackHead = (ushort)(newFrame.base + func.totalLocalsBytes);
                    }

                    case ObjType.NATIVE_FUNCTION:
                    {
                        ObjNative* nativeFn = (ObjNative*)callee;

                        double result = nativeFn.function();
                        vm.stackHead = funcOffset;
                        @push_val(vm, double, result);
                    }

                    default:
                        vm.error("Attempted to call non-callable object");
                        return RunResult.RUNTIME_ERR;
                }
            }

            case OpCode.RETURN.ordinal:
            {
                ObjFunction* func = vm.frame.function;
                ushort retSize = common::get_type_size(func.returnType);

                Byte[16] tmp; // enough for int/float/double/ptr/bool; expand later for structs
                Byte* retSrc = &vm.stack[vm.stackHead - retSize];
                for (int i=0; i<retSize; i++) tmp[i] = retSrc[i];

                ushort calleeOffset = (ushort)(vm.frame.base - uptr.sizeof);

                vm.frameCount--;
                if (vm.frameCount == 0) return RunResult.OK;

                vm.stackHead = calleeOffset;                 // pop callee + args + locals
                vm.frame = &vm.frames[vm.frameCount - 1];

                // push return value for caller
                for (int i=0; i<retSize; i++) vm.stack[vm.stackHead + i] = tmp[i];
                vm.stackHead += retSize;
            }

            // ---------- Fallback ----------

            default:
            {
                vm.error("Unknown opcode");
                return RunResult.RUNTIME_ERR;
            }
        }

    }
}


// ========== Error handling ==========

fn void Vm.error(Vm* this, String msg)
{
    log::errlogn("Runtime error: %s", msg);

    for (int i = this.frameCount - 1; i >= 0; i--) {
        CallFrame* frame = &this.frames[i];
        ObjFunction* function = frame.function;

        int instruction = (int)(frame.ip - &function.chunk.code[0]) - 1;
        if (instruction < 0) instruction = 0;

        log::errlogn("[line %d] in ", function.chunk.lines[instruction]);
        if (function.name == null) {
            log::errlogn("script");
        } else {
            log::errlogn("%s()", function.name.str);
        }
    }
}

fn void Vm.define_native(Vm* vm, String name, NativeFn function)
{
    ObjNative* nativeFn = common::create_obj_native(&function);
    common::allocatedConstants.push((Obj*)nativeFn);
    vm.globals.set(name, &nativeFn.obj);
}

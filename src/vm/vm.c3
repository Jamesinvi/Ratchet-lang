module vm;
import common;
import std::collections::map;
import debug;
import std::io;
import libc;
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
    OutStream output;

}

fn void Vm.init(Vm* this, ObjFunction* entryPoint, OutStream output)
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
    this.output = output;

    for(int i = 0; i < this.stackHead; i++){
        this.stack[i] = 0;
    }

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
        OpCode instruction = (OpCode)@read_u8(vm);
        debug::@print_instruction(vm);
        switch (instruction) @jump {

            // ---------- Constants ----------

            case OpCode.CONST_INT:      @read_const_and_push(vm, int);
            case OpCode.CONST_FLOAT:    @read_const_and_push(vm, float);        
            case OpCode.CONST_DOUBLE:   @read_const_and_push(vm, double);
            case OpCode.CONST_FUNC:     @read_const_and_push(vm, ObjFunction*);
            case OpCode.CONST_STRING:   @read_const_and_push(vm, ObjString*);
            case OpCode.CONST_TRUE:     @push_val(vm, bool, true);
            case OpCode.CONST_FALSE:    @push_val(vm, bool, false);
            case OpCode.CONST_NULL:     @push_val(vm, bool, false);


            // ---------- Locals ----------

            case OpCode.GET_LOCAL:
            {
                ushort slotIndex = @read_u16(vm);
                FrameSlotInfo info    = vm.frame.function.slots[slotIndex];
                ushort offset    = vm.frame.base + info.offset;
                switch (info.type) {
                    case ValueType.INT:         @read_local_and_push(vm, int, offset);
                    case ValueType.FLOAT:       @read_local_and_push(vm, float, offset);
                    case ValueType.DOUBLE:      @read_local_and_push(vm, double, offset);
                    case ValueType.BOOL:        @read_local_and_push(vm, bool, offset);
                    case ValueType.REF:      nextcase;
                    case ValueType.PTR:   @read_local_and_push(vm, Obj*, offset);
                    case ValueType.NULL:        @push_val(vm, bool, false); // or special NULL handling
                    case ValueType.STRUCT:{
                        Byte* src = &vm.stack[offset];
                        Byte* dst = &vm.stack[vm.stackHead];
                        ushort size = info.sizeInBytes;
                        // Check for overlaps. memcpy is undefined on overlaps.
                        assert(dst + size <= src || src + size <= dst);
                        libc::memcpy(dst, src, size);
                        vm.stackHead += size;

                    }
                    default:
                        vm.error("Unsupported local type in GET_LOCAL");
                        return RunResult.RUNTIME_ERR;
                }
            }

            case OpCode.SET_LOCAL:
            {
                ushort slotIndex = @read_u16(vm);
                FrameSlotInfo info = vm.frame.function.slots[slotIndex];
                ushort offset = vm.frame.base + info.offset;

                vm.stackHead -= info.sizeInBytes;
                libc::memcpy(&vm.stack[offset], &vm.stack[vm.stackHead], info.sizeInBytes);

            }

            case OpCode.GET_PROP_LOC:
            {
                ushort slotIndex = @read_u16(vm);
                ushort localOffset = @read_u16(vm);
                ushort fieldSize = @read_u16(vm);
                ValueType fieldType = (ValueType) @read_u8(vm);
                FrameSlotInfo info = vm.frame.function.slots[slotIndex];
                ushort offset = vm.frame.base + info.offset + localOffset;

                assert(localOffset + fieldSize <= info.sizeInBytes);

                switch (fieldType) {
                    case ValueType.INT:         @read_local_and_push(vm, int, offset);
                    case ValueType.FLOAT:       @read_local_and_push(vm, float, offset);
                    case ValueType.DOUBLE:      @read_local_and_push(vm, double, offset);
                    case ValueType.BOOL:        @read_local_and_push(vm, bool, offset);
                    case ValueType.REF:      nextcase;
                    case ValueType.PTR:   @read_local_and_push(vm, Obj*, offset);
                    case ValueType.NULL:        @push_val(vm, bool, false); // or special NULL handling
                    default:
                        vm.error("Handle some loading of structs and primitives");
                        return RunResult.RUNTIME_ERR;
                }
            }

            case OpCode.SET_PROP_LOC:
            {
                ushort slotIndex = @read_u16(vm);
                ushort localOffset = @read_u16(vm);
                ushort fieldSize = @read_u16(vm);
                ValueType fieldType = (ValueType) @read_u8(vm);
                FrameSlotInfo info = vm.frame.function.slots[slotIndex];
                ushort offset = vm.frame.base + info.offset + localOffset;

                vm.stackHead -= fieldSize;
                libc::memcpy(&vm.stack[offset], &vm.stack[vm.stackHead], fieldSize);

            }

            case OpCode.GET_PROP_REF:
            {
                ushort slotIndex   = @read_u16(vm);
                ushort localOffset = @read_u16(vm);
                ushort fieldSize = @read_u16(vm);

                ValueType fieldType = (ValueType)@read_u8(vm);

                FrameSlotInfo info = vm.frame.function.slots[slotIndex];
                ushort slotAddr = vm.frame.base + info.offset;

                ObjRef* r = @read_local(vm, ObjRef*, slotAddr);
                if (r == null || r.data == null) { vm.error("Null reference"); return RunResult.RUNTIME_ERR; }

                Byte* fieldAddr = (Byte*)r.data + localOffset;
                assert(localOffset + fieldSize <= r.sizeInBytes);

                switch (fieldType) {
                    case ValueType.INT:    { int v = @unaligned_load(*(int*)fieldAddr, int.alignof); @push_val(vm, int, v); }
                    case ValueType.FLOAT:  { float v = @unaligned_load(*(float*)fieldAddr, float.alignof); @push_val(vm, float, v); }
                    case ValueType.DOUBLE: { double v = @unaligned_load(*(double*)fieldAddr, double.alignof); @push_val(vm, double, v); }
                    case ValueType.BOOL:   { bool v = @unaligned_load(*(bool*)fieldAddr, bool.alignof); @push_val(vm, bool, v); }
                    case ValueType.REF: nextcase;
                    case ValueType.PTR:
                    {
                        Obj* v = @unaligned_load(*(Obj**)fieldAddr, uptr.alignof);
                        @push_val(vm, Obj*, v);
                    }
                    default: { vm.error("Unsupported field type in GET_PROP_REF"); return RunResult.RUNTIME_ERR; }
                }
            }

            case OpCode.SET_PROP_REF:
            {
                ushort slotIndex = @read_u16(vm);
                ushort localOffset = @read_u16(vm);
                ushort fieldSize = @read_u16(vm);
                ValueType fieldType = (ValueType)@read_u8(vm);

                FrameSlotInfo info = vm.frame.function.slots[slotIndex];
                ushort slotAddr = vm.frame.base + info.offset;

                // Local slot stores an ObjRef* (as pointer bytes)
                ObjRef* r = @read_local(vm, ObjRef*, slotAddr);
                if (r == null || r.data == null) { vm.error("Null reference"); return RunResult.RUNTIME_ERR; }

                // Optional bounds check
                if (localOffset + fieldSize > r.sizeInBytes) {
                    vm.error("Field write out of bounds");
                    return RunResult.RUNTIME_ERR;
                }

                Byte* fieldAddr = (Byte*)r.data + localOffset;

                // Pop RHS and store into referenced memory
                vm.stackHead -= fieldSize;
                libc::memcpy(fieldAddr, &vm.stack[vm.stackHead], fieldSize);
            }


            case OpCode.NEW_REF:
            {
                Byte tracked = @read_u8(vm);
                ValueType refTo  = (ValueType)@read_u8(vm);
                ushort sizeBytes = @read_u16(vm);

                // one allocation: [ObjRef header][payload bytes...]
                usz total = ObjRef.sizeof + sizeBytes;

                void* memBlock = tracked ? vm.trackedHeap.alloc(total) : vm.untrackedHeap.alloc(total); 
                ObjRef* r = common::create_obj_ref(false, refTo, sizeBytes, memBlock);
                if (tracked>0) {
                    vm.trackedHeap.track_alloc((Obj*)r);
                }else{
                    vm.untrackedHeap.track_alloc((Obj*)r);
                }

                @push_val(vm, ObjRef*, r);
            }


            // ---------- Globals: function-only ----------

            case OpCode.DEFINE_GLOBAL:
            {
                ushort nameOffset = @read_u16(vm);
                ObjString* nameObj = @read_const(vm, ObjString*, nameOffset);
                String name = nameObj.str;

                Obj* obj = @pop_val(vm, Obj*);
                vm.globals.set(name, obj);
            }

            case OpCode.GET_GLOBAL:
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

            case OpCode.JMP:
            {
                ushort offset = @read_u16(vm);
                vm.frame.ip += offset;
            }

            case OpCode.JMP_IF_FALSE:
            {
                ushort offset = @read_u16(vm);
                if (!@peek_val(vm, bool)) {
                    vm.frame.ip += offset;
                }
            }

            case OpCode.LOOP:
            {
                ushort offset = @read_u16(vm);
                vm.frame.ip -= offset;
            }

            // ----------- Casts ---------------------

            case OpCode.CAST_TO_STRING:
            {
                ValueType fromType = (ValueType)@read_u8(vm);
                String s;

                switch (fromType) {
                    case ValueType.INT:    s = string::tformat("%d", @pop_val(vm, int));
                    case ValueType.FLOAT:  s = string::tformat("%f", @pop_val(vm, float));
                    case ValueType.DOUBLE: s = string::tformat("%f", @pop_val(vm, double));
                    case ValueType.BOOL:   s = string::tformat("%b", @pop_val(vm, bool));
                    case ValueType.NULL:   s = "null"; 

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

            case OpCode.INT_LESS:        @compare(vm, int,    OP_LESS);
            case OpCode.INT_GREATER:     @compare(vm, int,    OP_GREATER);
            case OpCode.INT_EQUAL:       @compare(vm, int,    OP_EQUAL);

            case OpCode.FLOAT_LESS:      @compare(vm, float,  OP_LESS);
            case OpCode.FLOAT_GREATER:   @compare(vm, float,  OP_GREATER);
            case OpCode.FLOAT_EQUAL:     @compare(vm, float,  OP_EQUAL);

            case OpCode.DOUBLE_LESS:     @compare(vm, double, OP_LESS);
            case OpCode.DOUBLE_GREATER:  @compare(vm, double, OP_GREATER);
            case OpCode.DOUBLE_EQUAL:    @compare(vm, double, OP_EQUAL);

            case OpCode.NOT:
            {
                bool v = @pop_val(vm, bool);
                @push_val(vm, bool, !v);
            }

            // ---------- Arithmetic ----------

            case OpCode.INC_LOCAL:
            {
                ushort slotIndex = @read_u16(vm);
                FrameSlotInfo info    = vm.frame.function.slots[slotIndex];
                ushort offset    = vm.frame.base + info.offset;

                int v = @read_local(vm, int, offset);
                v += 1;

                Byte* dst = &vm.stack[offset];
                @unaligned_store(*(int*)dst, v, int.alignof);
            }

            case OpCode.ADD_INT:       @math(vm, int,    OP_ADD);
            case OpCode.SUB_INT:       @math(vm, int,    OP_SUB);
            case OpCode.MUL_INT:       @math(vm, int,    OP_MUL);
            case OpCode.DIV_INT:       @math(vm, int,    OP_DIV);
            case OpCode.NEGATE_INT:    @negate(vm, int);

            case OpCode.ADD_FLOAT:     @math(vm, float,  OP_ADD);
            case OpCode.SUB_FLOAT:     @math(vm, float,  OP_SUB);
            case OpCode.MUL_FLOAT:     @math(vm, float,  OP_MUL);
            case OpCode.DIV_FLOAT:     @math(vm, float,  OP_DIV);
            case OpCode.NEGATE_FLOAT:  @negate(vm, float);

            case OpCode.ADD_DOUBLE:    @math(vm, double, OP_ADD);
            case OpCode.SUB_DOUBLE:    @math(vm, double, OP_SUB);
            case OpCode.MUL_DOUBLE:    @math(vm, double, OP_MUL);
            case OpCode.DIV_DOUBLE:    @math(vm, double, OP_DIV);
            case OpCode.NEGATE_DOUBLE: @negate(vm, double);

            // ---------- Output ----------

            case OpCode.ECHO:
            {
                ValueType type = (ValueType)@read_u8(vm);

                switch (type) {
                    case ValueType.INT:         io::fprintfn(vm.output, "%d", @pop_val(vm, int));
                    case ValueType.FLOAT:       io::fprintfn(vm.output, "%f", @pop_val(vm, float));
                    case ValueType.DOUBLE:      io::fprintfn(vm.output, "%f", @pop_val(vm, double));
                    case ValueType.BOOL:        io::fprintfn(vm.output, "%s", @pop_val(vm, bool));
                    case ValueType.NULL:        io::fprintfn(vm.output, "null"); @pop_val(vm, bool);
                    case ValueType.STRUCT:      io::fprintfn(vm.output, "Struct"); @pop_val(vm, int);
                    case ValueType.PTR:   nextcase;
                    case ValueType.REF:
                    {
                        Obj* obj = @pop_val(vm, Obj*);
                        ObjType kind = obj.type;

                        switch (kind) {
                            case ObjType.STRING:            io::fprintfn(vm.output, "%s", ((ObjString*)obj).str);
                            case ObjType.FUNCTION:          io::fprintfn(vm.output, "fn: %s", ((ObjFunction*)obj).name.str);
                            case ObjType.REF:               io::fprintfn(vm.output, "ref: %s", ((ObjRef*)obj).refTo);
                            case ObjType.NATIVE_FUNCTION:   io::fprintfn(vm.output, "native fn");
                        }
                    }
                }
            }

            case OpCode.POP:
            {
                Byte size = @read_u8(vm);
                vm.stackHead -= size;
            }

            // ---------- Call / Return ----------

            case OpCode.CALL:
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

                        // Zero initialization on locals
                        ushort localsStart = newFrame.base + func.argsSizeInBytes;
                        ushort localsEnd   = newFrame.base + func.totalLocalsBytes;
                        libc::memset(&vm.stack[localsStart], 0, (usz)localsEnd - localsStart);

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

            case OpCode.RETURN:
            {
                ObjFunction* func = vm.frame.function;
                ushort retSize = func.returnTypeSize;

                Byte* retSrc = &vm.stack[vm.stackHead - retSize];
                ushort calleeOffset = (ushort)(vm.frame.base - uptr.sizeof);

                vm.frameCount--;
                if (vm.frameCount == 0) return RunResult.OK;

                vm.stackHead = calleeOffset;                 // pop callee + args + locals
                vm.frame = &vm.frames[vm.frameCount - 1];

                // push return value for caller
                libc::memcpy(&vm.stack[vm.stackHead],retSrc, retSize);
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

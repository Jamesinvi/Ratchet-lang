module vm;
import common;
import std::collections::list;
import std::collections::map;
import debug;
import std::io;
alias Chunk = common::Chunk;
alias VmStack = common::fixed_stack::FixedStack{Value};
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
    VmStack stack;
    CallFrame* frame;
    CallFrame[FRAMES_MAX] frames;
    int frameCount;
    HeapTracker trackedHeap;
    HeapTracker untrackedHeap;
    HashMap{String, Value} globals;
}

fn void Vm.init(Vm* this, ObjFunction* entryPoint){
    this.stack.size = 0;
    this.frameCount = 0;
    this.trackedHeap.init("TRACKED HEAP");
    this.untrackedHeap.init("UNTRACKED HEAP");
    this.globals.init(mem);

    this.stack.push(@new_function(entryPoint));
    this.frame = &this.frames[this.frameCount++];
    this.frame.function = entryPoint;
    this.frame.ip = (Byte*)&entryPoint.chunk.code[0];
    this.frame.slots = &this.stack.items[0];

    this.define_native("clock", &clock_native);
}

fn void Vm.deinit(Vm* this){
    this.trackedHeap.free();
    this.globals.free();
}
macro Byte @read_byte(Vm* vm){
    return *vm.frame.ip++;
}
macro ushort @read_ushort(Vm* vm){
    vm.frame.ip += 2;
    return (ushort)((vm.frame.ip[-2] << 8) | vm.frame.ip[-1]);
}

macro Value @read_const(Vm* vm){
    return vm.frame.function.chunk.constants[@read_byte(vm)];
}

macro Value @null_val(){
    return {.type = ValueType.NULL, .as.boolean = false};
}

macro Value @new_function(ObjFunction* obj){
    return {.type = ValueType.NO_GC_OBJ, .as.objRef = (Obj*)obj};
}

macro Value @new_bool(bool b){
    return {.type = ValueType.BOOL, .as.boolean = b};
}

macro Value @new_string(String s){
    return common::make_string(s, false);
}

macro @bin_op_greater(Vm* vm){
    Value right = vm.stack.pop_val();
    Value left = vm.stack.pop_val();
    switch(left.type){
        case ValueType.BOOL:   vm.stack.push(@new_bool(left.as.boolean   > right.as.boolean));
        case ValueType.INT:    vm.stack.push(@new_bool(left.as.intNum    > right.as.intNum));
        case ValueType.DOUBLE: vm.stack.push(@new_bool(left.as.doubleNum > right.as.doubleNum));
        case ValueType.FLOAT:  vm.stack.push(@new_bool(left.as.floatNum  > right.as.floatNum));
        default: vm.error("unsupported operation between left types");
    }
}

macro @bin_op_less(Vm* vm){
    Value right = vm.stack.pop_val();
    Value left = vm.stack.pop_val();
    switch(left.type){
        case ValueType.BOOL:   vm.stack.push(@new_bool(left.as.boolean   < right.as.boolean));
        case ValueType.INT:    vm.stack.push(@new_bool(left.as.intNum    < right.as.intNum));
        case ValueType.DOUBLE: vm.stack.push(@new_bool(left.as.doubleNum < right.as.doubleNum));
        case ValueType.FLOAT:  vm.stack.push(@new_bool(left.as.floatNum  < right.as.floatNum));
        default: vm.error("unsupported operation between these types");
    }
}

macro @bin_op_equal(Vm* vm){
    Value right = vm.stack.pop_val();
    Value left = vm.stack.pop_val();
    switch(left.type){
        case ValueType.BOOL:   vm.stack.push(@new_bool(left.as.boolean   == right.as.boolean));
        case ValueType.INT:    vm.stack.push(@new_bool(left.as.intNum    == right.as.intNum));
        case ValueType.DOUBLE: vm.stack.push(@new_bool(left.as.doubleNum == right.as.doubleNum));
        case ValueType.FLOAT:  vm.stack.push(@new_bool(left.as.floatNum  == right.as.floatNum));
        case ValueType.GC_OBJ:  nextcase;
        case ValueType.NO_GC_OBJ: {
            ObjString* rightObj = common::@as_string(&right);
            ObjString* leftObj = common::@as_string(&left);
            Value result = @new_bool(common::string_equals(rightObj.str,leftObj.str));
            vm.stack.push(result);

        }
        default: vm.error("unsupported operation between these types");
    }
}

macro @cast_top( Vm* vm, $SrcType, $DstType, $dstEnum, $srcField, $dstField)
{
    // Could pop/push but we can do it in place
    Value top = vm.stack.peek();
    $SrcType src = top.as.$eval($srcField);
    top.type = ValueType.$eval($dstEnum);
    top.as.$eval($dstField) = ($DstType)src;
}


const OP_ADD = 0;
const OP_SUB = 1;
const OP_MUL = 2;
const OP_DIV = 3;

macro @math_inc_or_dec(Vm* vm, $field, $op)
{
    Byte slot = @read_byte(vm);
    Value* v = &vm.frame.slots[slot];
    $switch $op:
        $case OP_ADD: v.as.$eval($field)++;
        $case OP_SUB: v.as.$eval($field)--;
        $default:
            $error("Unknown inc/dec op");
    $endswitch
    vm.stack.push(*v);
}
macro @math_bin_op(Vm* vm, $Type, $type, $field, $op)
{
    $Type right = vm.stack.pop_val().as.$eval($field);
    $Type left  = vm.stack.pop_val().as.$eval($field);
    Value result = {.type = ValueType.$eval($type)};

    $switch $op:
        $case OP_ADD:
            result.as.$eval($field) = left + right;
        $case OP_SUB:
            result.as.$eval($field) = left - right;
        $case OP_MUL:
            result.as.$eval($field) = left * right;
        $case OP_DIV:
            result.as.$eval($field) = left / right;
        $default:
            $error("Unknown bin op");
    $endswitch
    vm.stack.push(result);
}

macro @negate_op(Vm* vm, $Type, $type, $field){
    // We could pop/push here, instead we do it in place
    Value* top = vm.stack.peek_ref();
    $Type right = top.as.$eval($field);
    top.type = ValueType.$eval($type);
    top.as.$eval($field) = -right;
}

macro Value @pop_obj(Vm* this){
    Value rightVal = this.stack.pop_val();
    Obj* right = rightVal.get_obj();
    this.trackedHeap.release_obj(right);
    return rightVal;
}

macro @push_obj(Vm* this, Value v){
    Obj* object = (v.get_obj());
    this.trackedHeap.track_alloc(object);
    this.trackedHeap.retain_obj(object);
    this.stack.push(v);
}

fn RunResult run(Vm* vm){
    debug::@print_disassembly(vm);
    vm.frame = &vm.frames[vm.frameCount - 1];
    while(true){
        Byte instruction;
        debug::@print_instruction(vm);
        switch (instruction = @read_byte(vm)){
            case OpCode.RETURN.ordinal: {
                Value result = vm.stack.pop_val();
                int frameBase = (int)(vm.frame.slots - &vm.stack.items[0]);

                vm.frameCount--;

                if (vm.frameCount == 0) {
                    return RunResult.OK;
                }
                vm.stack.size = frameBase;

                vm.frame = &vm.frames[vm.frameCount - 1];
                vm.stack.push(result);
            }

            case OpCode.POP.ordinal:           vm.stack.pop_val();
            case OpCode.EQUAL.ordinal:         @bin_op_equal(vm);
            case OpCode.GREATER.ordinal:       @bin_op_greater(vm);
            case OpCode.LESS.ordinal:          @bin_op_less(vm);
            case OpCode.INT_LESS.ordinal: {
                Value right = vm.stack.pop_val();
                Value left = vm.stack.pop_val();
                vm.stack.push(@new_bool(left.as.intNum < right.as.intNum));
            }

            case OpCode.NOT.ordinal:           vm.stack.push(@new_bool(!vm.stack.pop_val().as.boolean));

            case OpCode.CONST_FALSE.ordinal:   vm.stack.push(@new_bool(false));
            case OpCode.CONST_TRUE.ordinal:    vm.stack.push(@new_bool(true));
            case OpCode.CONST_NULL.ordinal:    vm.stack.push(@null_val());

            case OpCode.NEGATE_INT.ordinal:    @negate_op(vm, int.typeid,     "INT",    "intNum");
            case OpCode.NEGATE_FLOAT.ordinal:  @negate_op(vm, float.typeid,   "FLOAT",  "floatNum");
            case OpCode.NEGATE_DOUBLE.ordinal: @negate_op(vm, double.typeid,  "DOUBLE", "doubleNum");

            case OpCode.INC_LOCAL.ordinal:    @math_inc_or_dec(vm,  "intNum",      OP_ADD);
            case OpCode.DEC_LOCAL.ordinal:    @math_inc_or_dec(vm,  "intNum",      OP_SUB);
           
            case OpCode.ADD_INT.ordinal:    @math_bin_op(vm, int.typeid,       "INT",    "intNum",      OP_ADD);
            case OpCode.ADD_FLOAT.ordinal:  @math_bin_op(vm, float.typeid,     "FLOAT",  "floatNum",    OP_ADD);
            case OpCode.ADD_DOUBLE.ordinal: @math_bin_op(vm, double.typeid,    "DOUBLE", "doubleNum",   OP_ADD);
        
            case OpCode.SUB_INT.ordinal:    @math_bin_op(vm, int.typeid,       "INT",    "intNum",      OP_SUB);
            case OpCode.SUB_FLOAT.ordinal:  @math_bin_op(vm, float.typeid,     "FLOAT",  "floatNum",    OP_SUB);
            case OpCode.SUB_DOUBLE.ordinal: @math_bin_op(vm, double.typeid,    "DOUBLE", "doubleNum",   OP_SUB);
                    
            case OpCode.MUL_INT.ordinal:    @math_bin_op(vm, int.typeid,       "INT",    "intNum",      OP_MUL);
            case OpCode.MUL_FLOAT.ordinal:  @math_bin_op(vm, float.typeid,     "FLOAT",  "floatNum",    OP_MUL);
            case OpCode.MUL_DOUBLE.ordinal: @math_bin_op(vm, double.typeid,    "DOUBLE", "doubleNum",   OP_MUL);
                    
            case OpCode.DIV_INT.ordinal:    @math_bin_op(vm, int.typeid,       "INT",    "intNum",      OP_DIV);
            case OpCode.DIV_FLOAT.ordinal:  @math_bin_op(vm, float.typeid,     "FLOAT",  "floatNum",    OP_DIV);
            case OpCode.DIV_DOUBLE.ordinal: @math_bin_op(vm, double.typeid,    "DOUBLE", "doubleNum",   OP_DIV);

            case OpCode.CONSTANT.ordinal:   vm.stack.push(@read_const(vm));

            case OpCode.CAST_I_F.ordinal:   @cast_top(vm, int.typeid,    float.typeid,  "FLOAT",  "intNum",    "floatNum");
            case OpCode.CAST_I_D.ordinal:   @cast_top(vm, int.typeid,    double.typeid, "DOUBLE", "intNum",    "doubleNum");
            case OpCode.CAST_F_I.ordinal:   @cast_top(vm, float.typeid,  int.typeid,    "INT",    "floatNum",  "intNum");
            case OpCode.CAST_F_D.ordinal:   @cast_top(vm, float.typeid,  double.typeid, "DOUBLE", "floatNum",  "doubleNum");
            case OpCode.CAST_D_I.ordinal:   @cast_top(vm, double.typeid, int.typeid,    "INT",    "doubleNum", "intNum");
            case OpCode.CAST_D_F.ordinal:   @cast_top(vm, double.typeid, float.typeid,  "FLOAT",  "doubleNum", "floatNum");

            case OpCode.CAST_TO_STRING.ordinal: {
                Value v = vm.stack.pop_val();
                // convert v -> String representation
                String s = common::value_to_string(&v);
                Value result = @new_string(s); // or build directly from value_to_string
                @push_obj(vm, result);
            }
            case OpCode.ECHO.ordinal:      common::print_value(vm.stack.pop_val());
            
            case OpCode.JMP_IF_FALSE.ordinal: {
                ushort offset = @read_ushort(vm);
                if (!(vm.stack.peek().as.boolean)) vm.frame.ip += offset;
                break;
            }
            case OpCode.JMP.ordinal: {
                ushort offset = @read_ushort(vm);
                vm.frame.ip += offset;
                break;
            }
            case OpCode.LOOP.ordinal: {
                ushort offset = @read_ushort(vm);
                vm.frame.ip -= offset;
                break;
            }

            case OpCode.DEFINE_GLOBAL.ordinal:{
                Value v = @read_const(vm);
                String name = common::@as_string(&v).str;
                vm.globals.set(name,vm.stack.pop_val());
            }
            case OpCode.SET_GLOBAL.ordinal:{
                Value v = @read_const(vm);
                String name = common::@as_string(&v).str;
                if(!vm.globals.set(name,vm.stack.peek())){
                    vm.globals.remove(name);
                    vm.error("Undefined variable");
                    return RunResult.RUNTIME_ERR;
                }
            }
            case OpCode.GET_GLOBAL.ordinal:{
                Value v = @read_const(vm);
                String name = common::@as_string(&v).str;
                Value? variable = vm.globals.get(name);
                if(catch err = variable){
                    vm.error("Undefined variable");
                    return RunResult.RUNTIME_ERR;
                }
                vm.stack.push(variable);
            }
            case OpCode.SET_LOCAL.ordinal:{
                Byte slot = @read_byte(vm);
                vm.frame.slots[slot] = vm.stack.peek();
            }
            case OpCode.GET_LOCAL.ordinal:{
                Byte slot = @read_byte(vm);
                vm.stack.push(vm.frame.slots[slot]);
            }
            case OpCode.CONCAT_STRING.ordinal:{
                Value rightVal = @pop_obj(vm);
                Value leftVal= @pop_obj(vm);
                ObjString* right = common::@as_string(&rightVal);
                ObjString* left =  common::@as_string(&leftVal);
                Value result = @new_string(left.str.concat(mem, right.str));
                @push_obj(vm,result);
            }
            case OpCode.CALL.ordinal:{
                Byte argCount = @read_byte(vm);
                vm.call_value(vm.stack.peek_at(argCount), argCount);
                vm.frame = &vm.frames[vm.frameCount -1];
            }
        }
        debug::@print_stack(vm);

    }
}

fn void Vm.call_value(Vm* vm, Value callee, int argCount){
    if(vm.frameCount == FRAMES_MAX){
        vm.error("Stack overflow");
        return;
    }
    Obj* calleeObj = callee.get_obj();
    switch (calleeObj.type) {
        case ObjType.FUNCTION:{
            ObjFunction* function = common::@as_func(&callee);
            CallFrame* frame = &vm.frames[vm.frameCount++];
            frame.function = function;
            frame.ip= (Byte*)&function.chunk.code[0];
            frame.slots = &vm.stack.items[vm.stack.size - argCount -1];
        }
        case ObjType.NATIVE_FUNCTION:{
            NativeFn native = common::@as_native(&callee).function;
            Value result = native(argCount, vm.stack.peek_at(argCount));
            vm.stack.size -= argCount + 1;
            vm.stack.push(result);
        }
        default: vm.error("invalid call operation");
    }
}

fn void Vm.error(Vm* vm, String msg){
    io::printfn("%s", msg);
    for (int i = vm.frameCount - 1; i >= 0; i--) {
        CallFrame* frame = &vm.frames[i];
        ObjFunction* function = frame.function;

        // frame.ip points to the NEXT instruction to execute,
        // so we subtract 1 to get the index of the last executed instruction.
        int instruction = (int)(frame.ip - &function.chunk.code[0]) - 1;
        if (instruction < 0) instruction = 0;

        io::printf("[line %d] in ", function.chunk.lines[instruction]);
        if (function.name == null) {
            io::printf("script\n");
        } else {
            io::printf("%s()\n", function.name.str);
        }
    }
}

fn void Vm.define_native(Vm* vm, String name, NativeFn function) {
    vm.stack.push(common::make_string(name, true));
    vm.stack.push(common::make_native(function));
    int nameIndex = vm.stack.size -2;
    int valueIndex = vm.stack.size -1;
    ObjString* nameObj = common::@as_string(&vm.stack.items[nameIndex]);
    vm.globals.set(nameObj.str, vm.stack.items[valueIndex]);
    vm.stack.pop_ref();
    vm.stack.pop_ref();
}
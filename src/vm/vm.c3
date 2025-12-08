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
    Value right = vm.stack.pop();
    Value left = vm.stack.pop();
    switch(left.type){
        case ValueType.BOOL:   vm.stack.push(@new_bool(left.as.boolean   > right.as.boolean));
        case ValueType.INT:    vm.stack.push(@new_bool(left.as.intNum    > right.as.intNum));
        case ValueType.DOUBLE: vm.stack.push(@new_bool(left.as.doubleNum > right.as.doubleNum));
        case ValueType.FLOAT:  vm.stack.push(@new_bool(left.as.floatNum  > right.as.floatNum));
        default: vm.error("unsupported operation between left types");
    }
}

macro @bin_op_less(Vm* vm){
    Value right = vm.stack.pop();
    Value left = vm.stack.pop();
    switch(left.type){
        case ValueType.BOOL:   vm.stack.push(@new_bool(left.as.boolean   < right.as.boolean));
        case ValueType.INT:    vm.stack.push(@new_bool(left.as.intNum    < right.as.intNum));
        case ValueType.DOUBLE: vm.stack.push(@new_bool(left.as.doubleNum < right.as.doubleNum));
        case ValueType.FLOAT:  vm.stack.push(@new_bool(left.as.floatNum  < right.as.floatNum));
        default: vm.error("unsupported operation between these types");
    }
}

macro @bin_op_equal(Vm* vm){
    Value right = vm.stack.pop();
    Value left = vm.stack.pop();
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

const OP_ADD = 0;
const OP_SUB = 1;
const OP_MUL = 2;
const OP_DIV = 3;

macro @math_bin_op(Vm* vm, $Type, $type, $field, $op)
{
    $Type right = vm.stack.pop().as.$eval($field);
    $Type left  = vm.stack.pop().as.$eval($field);
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
    $Type right = vm.stack.pop().as.$eval($field);
    vm.stack.push((Value){.type = ValueType.$eval($type), .as.$eval($field) = - right});
}

macro Value @pop_obj(Vm* this){
    Value rightVal = this.stack.pop();
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
        switch (instruction = @read_byte(vm)) {
            case OpCode.RETURN.ordinal: {
                Value result = vm.stack.pop();
                int frameBase = (int)(vm.frame.slots - &vm.stack.items[0]);

                vm.frameCount--;

                if (vm.frameCount == 0) {
                    return RunResult.OK;
                }
                vm.stack.size = frameBase;

                vm.frame = &vm.frames[vm.frameCount - 1];
                vm.stack.push(result);
            }

            case OpCode.POP.ordinal:           vm.stack.pop();
            case OpCode.EQUAL.ordinal:         @bin_op_equal(vm);
            case OpCode.GREATER.ordinal:       @bin_op_greater(vm);
            case OpCode.LESS.ordinal:          @bin_op_less(vm);

            case OpCode.NOT.ordinal:           vm.stack.push(@new_bool(!vm.stack.pop().as.boolean));

            case OpCode.CONST_FALSE.ordinal:   vm.stack.push(@new_bool(false));
            case OpCode.CONST_TRUE.ordinal:    vm.stack.push(@new_bool(true));
            case OpCode.CONST_NULL.ordinal:    vm.stack.push(@null_val());

            case OpCode.NEGATE_INT.ordinal:    @negate_op(vm, int.typeid,     "INT",    "intNum");
            case OpCode.NEGATE_FLOAT.ordinal:  @negate_op(vm, float.typeid,   "FLOAT",  "floatNum");
            case OpCode.NEGATE_DOUBLE.ordinal: @negate_op(vm, double.typeid,  "DOUBLE", "doubleNum");

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

            case OpCode.DEBUG.ordinal:      common::print_value(vm.stack.pop());
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
                vm.globals.set(name,vm.stack.pop());
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
    ObjFunction* function = common::@as_func(&callee);
    CallFrame* frame = &vm.frames[vm.frameCount++];
    frame.function = function;
    frame.ip= (Byte*)&function.chunk.code[0];
    frame.slots = &vm.stack.items[vm.stack.size - argCount -1];
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

fn void Vm.print_stack(Vm* this)
{
    io::printf("Stack |");
    int counter = 0;

    Value* begin = (Value*)&this.stack.items[0];
    Value* end   = (Value*)&this.stack.items[this.stack.size];

    for (Value* slot = begin; slot < end; slot++){
        io::printf("[ ");
        slot.debug_print();
        io::printf(" ]");
        counter++;
    }

    if (counter > 0) {
        io::printf("<---Top\n");
    } else {
        io::printf("\n");
    }
}

fn void Vm.print_disassembly(Vm* this)
{
    for(int i=0;i<this.frameCount;i++){
        io::printfn("function : '%s'", this.frames[i].function.name.str);
        print_function_and_children(this.frames[i].function);
    }
}

fn void print_function_and_children(ObjFunction* function) {
    if(function.name!=null){
        io::printfn("function : '%s'", function.name.str);
    }
    function.chunk.debug_print();

    // Also descend into function constants
    for (int i = 0; i < (int)function.chunk.constants.len(); i++) {
        Value* v = &function.chunk.constants[i];
        if (v.type == ValueType.NO_GC_OBJ || v.type == ValueType.GC_OBJ) {
            Obj* o = v.as.objRef;
            if (o.type == ObjType.FUNCTION) {
                ObjFunction* child = (ObjFunction*)o;
                print_function_and_children(child);
            }
        }
    }
}
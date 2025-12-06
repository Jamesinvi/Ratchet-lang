module vm;
import common;
import std::collections::list;
import std::collections::map;
import debug;
import common::stack;
import std::io;
alias Chunk = common::Chunk;
alias VmStack = common::stack::Stack{Value};

const MAX_STACK_SIZE = 512;

macro Byte @read_byte(Vm* vm){
    return *vm.ip++;
}

macro Value @read_const(Vm* vm){
    return vm.chunk.constants[@read_byte(vm)];
}

macro @debug_instruction(Vm* vm){
    $if (debug::DISASSMBLE_DURING_EXECUTION):
        common::dissassemble_instruction(vm.chunk,(int)(vm.ip - &vm.chunk.code[0]));
    $endif
}
macro @debug_print(Vm* vm){
    $if (debug::SHOW_STACK):
        vm.print_stack();
    $endif
}

macro Value @null_val(){
    return {.type = ValueType.NULL, .as.boolean = false};
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
        case ValueType.BOOL:   vm.stack.push(@new_bool(right.as.boolean > left.as.boolean));
        case ValueType.INT:    vm.stack.push(@new_bool(right.as.intNum > left.as.intNum));
        case ValueType.DOUBLE: vm.stack.push(@new_bool(right.as.doubleNum > left.as.doubleNum));
        case ValueType.FLOAT:  vm.stack.push(@new_bool(right.as.floatNum > left.as.floatNum));
        default: vm.error("unsupported operation between these types");
    }
}

macro @bin_op_less(Vm* vm){
    Value right = vm.stack.pop();
    Value left = vm.stack.pop();
    switch(left.type){
        case ValueType.BOOL:   vm.stack.push(@new_bool(right.as.boolean < left.as.boolean));
        case ValueType.INT:    vm.stack.push(@new_bool(right.as.intNum < left.as.intNum));
        case ValueType.DOUBLE: vm.stack.push(@new_bool(right.as.doubleNum < left.as.doubleNum));
        case ValueType.FLOAT:  vm.stack.push(@new_bool(right.as.floatNum < left.as.floatNum));
        default: vm.error("unsupported operation between these types");
    }
}

macro @bin_op_equal(Vm* vm){
    Value right = vm.stack.pop();
    Value left = vm.stack.pop();
    switch(left.type){
        case ValueType.BOOL:   vm.stack.push(@new_bool(right.as.boolean == left.as.boolean));
        case ValueType.INT:    vm.stack.push(@new_bool(right.as.intNum == left.as.intNum));
        case ValueType.DOUBLE: vm.stack.push(@new_bool(right.as.doubleNum == left.as.doubleNum));
        case ValueType.FLOAT:  vm.stack.push(@new_bool(right.as.floatNum == left.as.floatNum));
        case ValueType.GC_OBJ:  nextcase;
        case ValueType.NO_GC_OBJ: {
            ObjString* rightObj = right.get_obj_string();
            ObjString* leftObj = left.get_obj_string();
            Value result = @new_bool(common::string_equals(rightObj.str,leftObj.str));
            vm.stack.push(result);

        }
        default: vm.error("unsupported operation between these types");
    }
}

macro @bin_op_add(Vm* vm, $Type, $type, $field){
    $Type right = vm.stack.pop().as.$eval($field);
    $Type left = vm.stack.pop().as.$eval($field);
    vm.stack.push((Value){.type = ValueType.$eval($type), .as.$eval($field) = left + right});
}
macro @bin_op_sub(Vm* vm, $Type, $type, $field){
    $Type right = vm.stack.pop().as.$eval($field);
    $Type left = vm.stack.pop().as.$eval($field);
    vm.stack.push((Value){.type = ValueType.$eval($type), .as.$eval($field) = left - right});
}
macro @bin_op_mul(Vm* vm, $Type, $type, $field){
    $Type right = vm.stack.pop().as.$eval($field);
    $Type left = vm.stack.pop().as.$eval($field);
    vm.stack.push((Value){.type = ValueType.$eval($type), .as.$eval($field) = left * right});
}
macro @bin_op_div(Vm* vm, $Type, $type, $field){
    $Type right = vm.stack.pop().as.$eval($field);
    $Type left = vm.stack.pop().as.$eval($field);
    vm.stack.push((Value){.type = ValueType.$eval($type), .as.$eval($field) = left / right});
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


enum RunResult
{
    OK,
    RUNTIME_ERR,
}


struct Vm
{
    Chunk* chunk;
    Byte* ip;
    VmStack stack;
    HeapTracker trackedHeap;
    HeapTracker untrackedHeap;
    HashMap{String, Value} globals;
}

fn void Vm.init(Vm* this){
    this.stack.capacity = 0;
    this.stack.size = 0;
    this.trackedHeap.init("TRACKED HEAP");
    this.untrackedHeap.init("UNTRACKED HEAP");
    this.globals.init(mem);
}

fn void Vm.deinit(Vm* this){
    this.stack.free();
    this.trackedHeap.free();
    this.globals.free();
}

fn RunResult run(Vm* vm, Chunk* c){
    vm.chunk = c;
    vm.ip = (Byte*)&c.code[0];
    c.debug_print();
    while(true){
        Byte instruction;
        @debug_instruction(vm);
        switch (instruction = @read_byte(vm)) {
            case OpCode.RETURN.ordinal: {
                return RunResult.OK;
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

            case OpCode.ADD_INT.ordinal:    @bin_op_add(vm, int.typeid,       "INT",    "intNum");
            case OpCode.ADD_FLOAT.ordinal:  @bin_op_add(vm, float.typeid,     "FLOAT",  "floatNum");
            case OpCode.ADD_DOUBLE.ordinal: @bin_op_add(vm, double.typeid,    "DOUBLE", "doubleNum");
        
            case OpCode.SUB_INT.ordinal:    @bin_op_sub(vm, int.typeid,       "INT",    "intNum");
            case OpCode.SUB_FLOAT.ordinal:  @bin_op_sub(vm, float.typeid,     "FLOAT",  "floatNum");
            case OpCode.SUB_DOUBLE.ordinal: @bin_op_sub(vm, double.typeid,    "DOUBLE", "doubleNum");
                    
            case OpCode.MUL_INT.ordinal:    @bin_op_mul(vm, int.typeid,       "INT",    "intNum");
            case OpCode.MUL_FLOAT.ordinal:  @bin_op_mul(vm, float.typeid,     "FLOAT",  "floatNum");
            case OpCode.MUL_DOUBLE.ordinal: @bin_op_mul(vm, double.typeid,    "DOUBLE", "doubleNum");
        
            case OpCode.DIV_INT.ordinal:    @bin_op_div(vm, int.typeid,       "INT",    "intNum");
            case OpCode.DIV_FLOAT.ordinal:  @bin_op_div(vm, float.typeid,     "FLOAT",  "floatNum");
            case OpCode.DIV_DOUBLE.ordinal: @bin_op_div(vm, double.typeid,    "DOUBLE", "doubleNum");

            case OpCode.CONSTANT.ordinal:   vm.stack.push(@read_const(vm));

            case OpCode.DEBUG.ordinal:      common::print_value(vm.stack.pop());

            case OpCode.DEFINE_GLOBAL.ordinal:{
                Value v = @read_const(vm);
                String name = v.get_obj_string().str;
                vm.globals.set(name,vm.stack.pop());
            }
            case OpCode.SET_GLOBAL.ordinal:{
                Value v = @read_const(vm);
                String name = v.get_obj_string().str;
                if(!vm.globals.set(name,vm.stack.peek())){
                    vm.globals.remove(name);
                    vm.error("Undefined variable");
                    return RunResult.RUNTIME_ERR;
                }
            }
            case OpCode.GET_GLOBAL.ordinal:{
                Value v = @read_const(vm);
                String name = v.get_obj_string().str;
                Value? variable = vm.globals.get(name);
                if(catch err = variable){
                    vm.error("Undefined variable");
                    return RunResult.RUNTIME_ERR;
                }
                vm.stack.push(variable);
            }
            case OpCode.CONCAT_STRING.ordinal:{
                Value rightVal = @pop_obj(vm);
                Value leftVal= @pop_obj(vm);
                ObjString* right = rightVal.get_obj_string();
                ObjString* left = leftVal.get_obj_string();
                Value result = @new_string(left.str.concat(mem, right.str));
                @push_obj(vm,result);
            }
        }
        @debug_print(vm);

    }
}

fn void Vm.error(Vm* this, String msg){
    io::printfn(msg);
}
fn void Vm.print_stack(Vm* this)
{
    io::printf("Stack |");
    int counter= 0;
    for(Value* slot=this.stack.items;slot<&this.stack.items[this.stack.size];slot++)
    {
      io::printf("[ ");
      slot.debug_print();
      io::printf(" ]");
      counter++;
    }
    if(counter>0){
        io::printf("<---Top\n");
    }else{
        io::printf("\n");
    }
}
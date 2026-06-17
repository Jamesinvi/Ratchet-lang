module vm;
import common;
import runtime;
import debug;
import std::io;
import log;

alias Byte = char;


const FRAMES_MAX = 64;
const STACK_MAX  = (FRAMES_MAX * Byte::max);

faultdef RUNTIME_ERROR;

enum RunResult
{
    OK,
    RUNTIME_ERR,
}

enum VmBinOp
{
	ADD,
	SUB,
	MUL,
	DIV,
}

struct Vm
{
    Byte[STACK_MAX] 		stack;
    StackFrame[FRAMES_MAX] 	frames;
    StackFrame* 			frame;
	BCProgram* 				program;
	BCInstruction* 			instruction;
    HeapTracker 			trackedHeap;
    HeapTracker 			untrackedHeap;
    OutStream 				output;
    int 					frameCount;
	bool 					running;
	sz 						stackHead;
}

fn void Vm.init(Vm* this, BCProgram* program, OutStream output)
{
    this.program = program;
    this.output = output;
	for(sz i = 0; i < STACK_MAX; i++){
		this.stack[i] = 0;
	}
}

fn RunResult run(Vm* vm)
{
	vm.running = true;
    vm.instruction = &vm.program.instructions[0];
	vm.frameCount++;
	vm.frame = &vm.frames[vm.frameCount -1];
	vm.frame.base = vm.stackHead;

	do
	{
		log::logn("%s", vm.instruction.opCode);
		switch(vm.instruction.opCode)
		{
			case BCOpCode.CONSTI:	vm.const_op(int);
			case BCOpCode.CONSTF:	vm.const_op(float);
			case BCOpCode.CONSTD:	vm.const_op(double);
			case BCOpCode.MOVI:		vm.mov_op(int);
			case BCOpCode.MOVF:		vm.mov_op(float);
			case BCOpCode.MOVD:		vm.mov_op(double);
			case BCOpCode.ADDI:		vm.bin_math_op(int, VmBinOp.ADD);
			case BCOpCode.ADDF:		vm.bin_math_op(float, VmBinOp.ADD);
			case BCOpCode.ADDD:		vm.bin_math_op(double, VmBinOp.ADD);
			case BCOpCode.SUBI:		vm.bin_math_op(int, VmBinOp.SUB);
			case BCOpCode.MULI:		vm.bin_math_op(int, VmBinOp.MUL);
			case BCOpCode.DIVI:		vm.bin_math_op(int, VmBinOp.DIV);
			case BCOpCode.RETURN:
				vm.running = false;
			default:
				log::errlog("%s not currently supported", vm.instruction.opCode);
				return RunResult.RUNTIME_ERR;
		}
		vm.instruction++;
	} while(vm.running);

	vm.print_stack();
	return RunResult.OK;
}


macro Vm.const_op(Vm* vm, $Type)
{
	$Type* dst = ($Type*)&vm.stack[vm.frame.base + vm.instruction.destOffset];
	$Type field;
	$switch $Type:
		$case int: 		field = vm.instruction.immInt;
		$case float: 	field = vm.instruction.immFloat;
		$case double: 	field = vm.instruction.immDouble;
		$case bool: 	field = vm.instruction.immBool;
	$endswitch
	*dst = field;
}

macro Vm.mov_op(Vm* vm, $Type)
{
	$Type* dst = ($Type*)&vm.stack[vm.frame.base + vm.instruction.destOffset];
	$Type* src = ($Type*)&vm.stack[vm.frame.base + vm.instruction.leftOffset];
	$Type value = *src;
	*dst = value;
}

macro Vm.bin_math_op(Vm* vm, $Type, VmBinOp $op)
{
	$Type* dst = ($Type*)&vm.stack[vm.frame.base + vm.instruction.destOffset];
	$Type* left = ($Type*)&vm.stack[vm.frame.base + vm.instruction.leftOffset];
	$Type* right = ($Type*)&vm.stack[vm.frame.base + vm.instruction.rightOffset];
	$Type leftVal = *left;
	$Type rightVal = *right;
	$Type result;
	$switch $op:
		$case VmBinOp.ADD: result = leftVal + rightVal;
		$case VmBinOp.SUB: result = leftVal - rightVal;
		$case VmBinOp.MUL: result = leftVal * rightVal;
		$case VmBinOp.DIV: result = leftVal / rightVal;
	$endswitch
	*dst = result;
}

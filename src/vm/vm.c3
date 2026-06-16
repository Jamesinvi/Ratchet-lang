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
			case BCOpCode.CONSTI:	
			{
    			int* dst = (int*)&vm.stack[vm.frame.base + vm.instruction.destOffset];
				mem::store(dst, vm.instruction.immInt, int::alignment);
			}
			case BCOpCode.MOVI:
			{
    			int* dst = (int*)&vm.stack[vm.frame.base + vm.instruction.destOffset];
    			int* src = (int*)&vm.stack[vm.frame.base + vm.instruction.leftOffset];
				int value = mem::load(src, int::alignment);
				mem::store(dst, value, int::alignment);
			}
			case BCOpCode.ADDI:		vm.bin_op(int, VmBinOp.ADD);
			case BCOpCode.SUBI:		vm.bin_op(int, VmBinOp.SUB);
			case BCOpCode.MULI:		vm.bin_op(int, VmBinOp.MUL);
			case BCOpCode.DIVI:		vm.bin_op(int, VmBinOp.DIV);
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

macro Vm.bin_op(Vm* vm, $Type, VmBinOp $op)
{
	$Type* dst = ($Type*)&vm.stack[vm.frame.base + vm.instruction.destOffset];
	$Type* left = ($Type*)&vm.stack[vm.frame.base + vm.instruction.leftOffset];
	$Type* right = ($Type*)&vm.stack[vm.frame.base + vm.instruction.rightOffset];
	$Type leftVal = mem::load(left, $Type::alignment);
	$Type rightVal = mem::load(right, $Type::alignment);
	$Type result;
	$switch $op:
		$case VmBinOp.ADD: result = leftVal + rightVal;
		$case VmBinOp.SUB: result = leftVal - rightVal;
		$case VmBinOp.MUL: result = leftVal * rightVal;
		$case VmBinOp.DIV: result = leftVal / rightVal;
	$endswitch
	mem::store(dst, result, $Type::alignment);
}

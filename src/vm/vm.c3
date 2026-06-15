module vm;
import common;
import runtime;
import debug;
import std::io;
import log;

alias Byte = char;


const FRAMES_MAX = 64;
const STACK_MAX  = (FRAMES_MAX * Byte::max);

// // Helpers for Math operation macros
// const OP_LESS    = 0;
// const OP_GREATER = 1;
// const OP_EQUAL   = 2;
// const OP_ADD     = 3;
// const OP_SUB     = 4;
// const OP_MUL     = 5;
// const OP_DIV     = 6;
// const OP_NEGATE  = 7;

faultdef RUNTIME_ERROR;



enum RunResult
{
    OK,
    RUNTIME_ERR,
}

struct Vm
{
    Byte[STACK_MAX] stack;
	BCProgram* 		program;
    ushort stackHead;
    int frameCount;
	BCInstruction* instruction;
    HeapTracker trackedHeap;
    HeapTracker untrackedHeap;
    OutStream output;
	bool running;
}

fn void Vm.init(Vm* this, BCProgram* program, OutStream output)
{
    this.program = program;
    this.output = output;
}

fn RunResult run(Vm* vm)
{
	vm.running = true;
    vm.instruction = &vm.program.instructions[0];
	while(vm.running)
	{
		log::logn("%s", vm.instruction.opCode);
		switch(vm.instruction.opCode)
		{
			case BCOpCode.CONSTI:	
			{
    			int* dst = (int*)&vm.stack[vm.instruction.destOffset];
				mem::store(dst, vm.instruction.immInt, int::alignment);
			}
			case BCOpCode.MOVI:
			{
    			int* dst = (int*)&vm.stack[vm.instruction.destOffset];
    			int* src = (int*)&vm.stack[vm.instruction.leftOffset];
				int value = mem::load(src, int::alignment);
				mem::store(dst, value, int::alignment);
			}
			case BCOpCode.ADDI:
			{
    			int* dst = (int*)&vm.stack[vm.instruction.destOffset];
    			int* left = (int*)&vm.stack[vm.instruction.leftOffset];
    			int* right = (int*)&vm.stack[vm.instruction.rightOffset];
				int leftVal = mem::load(left, int::alignment);
				int rightVal = mem::load(right, int::alignment);
				mem::store(dst, leftVal+ rightVal, int::alignment);
			}
			case BCOpCode.RETURN:
				vm.running = false;
			default:
				log::errlog("%s not currently supported", vm.instruction.opCode);
				return RunResult.RUNTIME_ERR;
		}
		if(vm.running){
			vm.instruction++;
		}
	}

	int* src = (int*)&vm.stack[16];
	int value = mem::load(src, int::alignment);
	log::logn("%s", value);
	return RunResult.OK;
}


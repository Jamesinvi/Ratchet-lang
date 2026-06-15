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
	int[32]  intRegisters;
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
		switch(vm.instruction.opCode)
		{
			case BCOpCode.CONSTI:
				vm.intRegisters[vm.instruction.dest] = vm.instruction.immInt;
			case BCOpCode.MOVI:
					vm.intRegisters[vm.instruction.dest] = vm.intRegisters[vm.instruction.left];
			case BCOpCode.ADDI:
				vm.intRegisters[vm.instruction.dest] = vm.intRegisters[vm.instruction.left] + vm.intRegisters[vm.instruction.right];
			case BCOpCode.STORI:
				vm.intRegisters[vm.instruction.dest] = vm.intRegisters[vm.instruction.left];
			case BCOpCode.RET:
				vm.running = false; // Placeholder
			default:
				log::errlog("%s not currently supported", vm.instruction.opCode);
				return RunResult.RUNTIME_ERR;
		}
		if(vm.running){
			vm.instruction++;
		}
	}
	for	(sz i = 0; i< 32; i++)
	{
		log::log("%s |", vm.intRegisters[i]);
	}
	log::log("\n");

	return RunResult.OK;
}


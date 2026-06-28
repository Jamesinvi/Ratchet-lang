module vm;
import common;
import runtime;
import debug;
import std::io;
import log;
import std::core::mem;

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
	BCInstruction* 			instructionPtr;
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
    vm.instructionPtr = &vm.program.instructions[0];
	vm.frameCount++;
	vm.frame = &vm.frames[vm.frameCount -1];
	vm.frame.base = 0;
	vm.frame.size = vm.program.functions[0].frameSize;
	vm.stackHead = vm.program.functions[0].frameSize;

	while(vm.running) {
		BCInstruction* inst = vm.instructionPtr;
		vm.instructionPtr++; 
		
		log::logn("%s", inst.opCode);
		switch(inst.opCode)
		{
			case BCOpCode.CONSTI:	vm.const_op(inst, int);
			case BCOpCode.CONSTF:	vm.const_op(inst, float);
			case BCOpCode.CONSTD:	vm.const_op(inst, double);
			case BCOpCode.CONSTB:	vm.const_op(inst, bool);
			case BCOpCode.MOVI:		vm.mov_op(inst, int);
			case BCOpCode.MOVF:		vm.mov_op(inst, float);
			case BCOpCode.MOVD:		vm.mov_op(inst, double);
			case BCOpCode.ADDI:		vm.bin_math_op(inst, int, VmBinOp.ADD);
			case BCOpCode.ADDF:		vm.bin_math_op(inst, float, VmBinOp.ADD);
			case BCOpCode.ADDD:		vm.bin_math_op(inst, double, VmBinOp.ADD);
			case BCOpCode.SUBI:		vm.bin_math_op(inst, int, VmBinOp.SUB);
			case BCOpCode.MULI:		vm.bin_math_op(inst, int, VmBinOp.MUL);
			case BCOpCode.DIVI:		vm.bin_math_op(inst, int, VmBinOp.DIV);
			case BCOpCode.CALL:
			{
				BCCallInfo callInfo = vm.program.callInfos[inst.callInfoIdx];
				BCFunction callee = vm.program.functions[callInfo.calleeIdx];
				// Setup the new stack frame
				StackFrame* callerFrame = vm.frame; // Store the old one to copy arguments into the new one 
				vm.frameCount++;
				vm.frame = &vm.frames[vm.frameCount -1];
				vm.frame.base = vm.stackHead;
				vm.frame.size = callee.frameSize;
				vm.stackHead += callee.frameSize;
				vm.frame.returnPtr = vm.instructionPtr;
				vm.instructionPtr = &vm.program.instructions[callee.instructionsStart];
				vm.frame.returnDestOffset = callInfo.returnDestOffset;
				vm.frame.returnSize = callInfo.returnSize;

				// Copy call arguments into the new stack frame
				short paramOffset = 0; // first param is @_00
				for(int i = callInfo.argsStart; i < callInfo.argsEnd; i++){
					BCCallArg* arg = &vm.program.callArgs[i];
					Byte* src = &vm.stack[callerFrame.base + arg.callerOffset];
					Byte* dst = &vm.stack[vm.frame.base + paramOffset];
					// TODO: Alignment here is not correct, so for now just copy byte-by-byte
					mem::copy(dst, src, (sz)arg.size, 1, 1);
					paramOffset += arg.size; // later use real param offsets/alignment
				}
			}
			case BCOpCode.RETURN:
				short returnSourceOffset = inst.leftOffset;
				BCInstruction* returnPtr = vm.frame.returnPtr;
				sz returnFrameBase = vm.frame.base;
				short offset = vm.frame.returnDestOffset;
				short returnSize = vm.frame.returnSize;
				vm.frameCount--;
				if(vm.frameCount == 0){
					// Terminate the vm if we're returning from program()
					vm.stackHead = 0;
					vm.running = false;
				}else{
					// Copy the return value in the caller's stack frame at the specified offset
					Byte* src = &vm.stack[returnFrameBase + returnSourceOffset];
					vm.stackHead = returnFrameBase;
					vm.frame = &vm.frames[vm.frameCount -1];
					Byte* dest = &vm.stack[vm.frame.base + offset];
					// TODO: Alignment here is not correct, so for now just copy byte-by-byte
					mem::copy(dest, src, (sz)returnSize, 1, 1);
					vm.instructionPtr = returnPtr;
				}
			default:
				log::errlog("%s not currently supported", inst.opCode);
				return RunResult.RUNTIME_ERR;
		}
	} 

	vm.print_stack();
	return RunResult.OK;
}


macro Vm.const_op(Vm* vm, BCInstruction* inst, $Type)
{
	$Type* dst = ($Type*)&vm.stack[vm.frame.base + inst.destOffset];
	$Type field;
	$switch $Type:
		$case int: 		field = inst.immInt;
		$case float: 	field = inst.immFloat;
		$case double: 	field = inst.immDouble;
		$case bool: 	field = inst.immBool;
	$endswitch
	*dst = field;
}

macro Vm.mov_op(Vm* vm, BCInstruction* inst, $Type)
{
	$Type* dst = ($Type*)&vm.stack[vm.frame.base + inst.destOffset];
	$Type* src = ($Type*)&vm.stack[vm.frame.base + inst.leftOffset];
	$Type value = *src;
	*dst = value;
}

macro Vm.bin_math_op(Vm* vm, BCInstruction* inst, $Type, VmBinOp $op)
{
	$Type* dst = ($Type*)&vm.stack[vm.frame.base + inst.destOffset];
	$Type* left = ($Type*)&vm.stack[vm.frame.base + inst.leftOffset];
	$Type* right = ($Type*)&vm.stack[vm.frame.base + inst.rightOffset];
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

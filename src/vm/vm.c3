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

enum VmMathOp
{
	ADD,
	SUB,
	MUL,
	DIV,
}

enum VmCmpOp
{
	EQ,
	NEQ,
	LESS,
	GREATER,
	AND,
	OR,
}

struct Vm
{
    Byte[STACK_MAX] 		stack;
    StackFrame[FRAMES_MAX] 	frames;
    StackFrame* 			frame;
	BCProgram* 				program;
	BCInstruction* 			instructionPtr;
	BCInstruction* 			instructions;
	BCFunction* 			functions;
	BCBlock* 				blocks;
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
	if(vm.program.functions.len() == 0){
		return RunResult.OK;
	}
	vm.running = true;
	vm.functions = vm.program.functions.entries;
	vm.instructions = vm.program.instructions.entries;
	vm.blocks = vm.program.blocks.entries;
    vm.instructionPtr = &vm.instructions[0];
	vm.frameCount++;
	vm.frame = &vm.frames[vm.frameCount -1];
	vm.frame.base = 0;
	vm.frame.size = vm.functions[0].frameSize;
	vm.stackHead = vm.functions[0].frameSize;

	while(vm.running) {
		BCInstruction* inst = vm.instructionPtr;
		vm.instructionPtr++; 
		switch(inst.opCode)
		{
			case BCOpCode.NOP:		continue;
		    // Const
			case BCOpCode.CONSTI:	vm.const_op(inst, int);
			case BCOpCode.CONSTF:	vm.const_op(inst, float);
			case BCOpCode.CONSTD:	vm.const_op(inst, double);
			case BCOpCode.CONSTB:	vm.const_op(inst, bool);
			// Less
			case BCOpCode.LESSI:	vm.cmp_op(inst, int, VmCmpOp.LESS);
			case BCOpCode.LESSF:	vm.cmp_op(inst, float, VmCmpOp.LESS);
			case BCOpCode.LESSD:	vm.cmp_op(inst, double, VmCmpOp.LESS);
			case BCOpCode.LESSI_IM:	vm.cmp_op_immediate(inst, int, VmCmpOp.LESS);
			// Greater
			case BCOpCode.GREATERI:	vm.cmp_op(inst, int, VmCmpOp.GREATER);
			case BCOpCode.GREATERF:	vm.cmp_op(inst, float, VmCmpOp.GREATER);
			case BCOpCode.GREATERD:	vm.cmp_op(inst, double, VmCmpOp.GREATER);
			// Logic
			case BCOpCode.AND:		vm.cmp_op(inst, bool, VmCmpOp.AND);
			case BCOpCode.OR:		vm.cmp_op(inst, bool, VmCmpOp.OR);
			// Mov
			case BCOpCode.MOVI:		vm.mov_op(inst, int);
			case BCOpCode.MOVF:		vm.mov_op(inst, float);
			case BCOpCode.MOVD:		vm.mov_op(inst, double);
			case BCOpCode.MOVB:		vm.mov_op(inst, bool);
			case BCOpCode.MOV_BYTES:
			{
				Byte* dst = (Byte*)&vm.stack[vm.frame.base + inst.destOffset];
				Byte* src = (Byte*)&vm.stack[vm.frame.base + inst.leftOffset];
				// memmove handles overlapping memory correctly. memcpy is undefined
				mem::move(dst, src, inst.byteCount);
			}
			// Add
			case BCOpCode.INCREMENT:
			{
				int* v = (int*)&vm.stack[vm.frame.base + inst.destOffset];
				*v  = (*v) + 1;

			}
			case BCOpCode.ADDI:		vm.bin_math_op(inst, int, VmMathOp.ADD);
			case BCOpCode.ADDF:		vm.bin_math_op(inst, float, VmMathOp.ADD);
			case BCOpCode.ADDD:		vm.bin_math_op(inst, double, VmMathOp.ADD);
			case BCOpCode.ADDI_IM:	vm.bin_math_op_immediate(inst, int, VmMathOp.ADD);
			// Sub
			case BCOpCode.SUBI:		vm.bin_math_op(inst, int, VmMathOp.SUB);
			case BCOpCode.SUBF:		vm.bin_math_op(inst, float, VmMathOp.SUB);
			case BCOpCode.SUBD:		vm.bin_math_op(inst, double, VmMathOp.SUB);
			// Mul
			case BCOpCode.MULI:		vm.bin_math_op(inst, int, VmMathOp.MUL);
			case BCOpCode.MULF:		vm.bin_math_op(inst, float, VmMathOp.MUL);
			case BCOpCode.MULD:		vm.bin_math_op(inst, double, VmMathOp.MUL);
			// Div
			case BCOpCode.DIVI:		vm.bin_math_op(inst, int, VmMathOp.DIV);
			case BCOpCode.DIVF:		vm.bin_math_op(inst, float, VmMathOp.DIV);
			case BCOpCode.DIVD:		vm.bin_math_op(inst, double, VmMathOp.DIV);
			// Echo
			case BCOpCode.ECHOI:	vm.echo(inst, int);
			case BCOpCode.ECHOF:	vm.echo(inst, float);
			case BCOpCode.ECHOD:	vm.echo(inst, double);
			case BCOpCode.ECHOB:	vm.echo(inst, bool);
			// Control flow
			case BCOpCode.BRANCH_IF_FALSE:
			{
			    bool* condition = (bool*)&vm.stack[vm.frame.base + inst.leftOffset];
			    if(!*condition){
			        BCBlock* block = &vm.blocks[inst.blockToJumpTo];
		            vm.instructionPtr = &vm.instructions[(sz)block.instructionsStart]; 
			    }
			}
            case BCOpCode.JUMP:
            {
                BCBlock* block = &vm.blocks[inst.blockToJumpTo];
                vm.instructionPtr = &vm.instructions[(sz)block.instructionsStart]; 
            }
			case BCOpCode.CALL:
			{
				BCCallInfo callInfo = vm.program.callInfos[inst.callInfoIdx];
				BCFunction callee = vm.functions[callInfo.calleeIdx];
				// Setup the new stack frame
				StackFrame* callerFrame = vm.frame; // Store the old one to copy arguments into the new one 
				vm.frameCount++;
				vm.frame = &vm.frames[vm.frameCount -1];
				vm.frame.base = vm.stackHead;
				vm.frame.size = callee.frameSize;
				vm.stackHead += callee.frameSize;
				vm.frame.returnPtr = vm.instructionPtr;
				vm.instructionPtr = &vm.instructions[vm.blocks[callee.blocksStart].instructionsStart];
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

	// vm.print_stack();
	return RunResult.OK;
}

macro Vm.echo(Vm* vm, BCInstruction* inst, $Type)
{
	$Type* val = ($Type*)&vm.stack[vm.frame.base + inst.leftOffset];
	// use the vm output stream. stdout by default
    io::fprintfn(vm.output, "%s", *val);
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

macro Vm.cmp_op(Vm* vm, BCInstruction* inst, $Type, VmCmpOp $op)
{
	bool* dst = (bool*)&vm.stack[vm.frame.base + inst.destOffset];
	$Type* left = ($Type*)&vm.stack[vm.frame.base + inst.leftOffset];
	$Type* right = ($Type*)&vm.stack[vm.frame.base + inst.rightOffset];
	bool result;
	$switch $op:
		$case VmCmpOp.EQ: 		result = *left == *right;
		$case VmCmpOp.NEQ: 		result = *left != *right;
		$case VmCmpOp.LESS: 	result = *left < *right;
		$case VmCmpOp.GREATER: 	result = *left > *right;
		$case VmCmpOp.AND: 		result = *left && *right;
		$case VmCmpOp.OR: 		result = *left || *right;
	$endswitch
	*dst = result;
}

macro Vm.bin_math_op(Vm* vm, BCInstruction* inst, $Type, VmMathOp $op)
{
	$Type* dst = ($Type*)&vm.stack[vm.frame.base + inst.destOffset];
	$Type* left = ($Type*)&vm.stack[vm.frame.base + inst.leftOffset];
	$Type* right = ($Type*)&vm.stack[vm.frame.base + inst.rightOffset];
	$Type leftVal = *left;
	$Type rightVal = *right;
	$Type result;
	$switch $op:
		$case VmMathOp.ADD: result = leftVal + rightVal;
		$case VmMathOp.SUB: result = leftVal - rightVal;
		$case VmMathOp.MUL: result = leftVal * rightVal;
		$case VmMathOp.DIV: result = leftVal / rightVal;
	$endswitch
	*dst = result;
}

macro Vm.bin_math_op_immediate(Vm* vm, BCInstruction* inst, $Type, VmMathOp $op)
{
	$Type* dst = ($Type*)&vm.stack[vm.frame.base + inst.destOffset];
	$Type* left = ($Type*)&vm.stack[vm.frame.base + inst.leftOffset];
	$Type leftVal = *left;
	$Type rightVal;
	$switch $Type:
		$case int: 		rightVal = inst.immInt;
		$case float:	rightVal = inst.immFloat;
		$case double: 	rightVal = inst.immDouble;
	$endswitch
	$Type result;
	$switch $op:
		$case VmMathOp.ADD: result = leftVal + rightVal;
		$case VmMathOp.SUB: result = leftVal - rightVal;
		$case VmMathOp.MUL: result = leftVal * rightVal;
		$case VmMathOp.DIV: result = leftVal / rightVal;
	$endswitch
	*dst = result;
}



macro Vm.cmp_op_immediate(Vm* vm, BCInstruction* inst, $Type, VmCmpOp $op)
{
	bool* dst = (bool*)&vm.stack[vm.frame.base + inst.destOffset];
	$Type* left = ($Type*)&vm.stack[vm.frame.base + inst.leftOffset];
	$Type right;
	bool result;
	$switch $Type:
		$case int: 		right = inst.immInt;
		$case float:	right = inst.immFloat;
		$case double: 	right = inst.immDouble;
	$endswitch
	$switch $op:
		$case VmCmpOp.EQ: 		result = *left == right;
		$case VmCmpOp.NEQ: 		result = *left != right;
		$case VmCmpOp.LESS: 	result = *left < right;
		$case VmCmpOp.GREATER: 	result = *left > right;
		$case VmCmpOp.AND: 		result = *left && right;
		$case VmCmpOp.OR: 		result = *left || right;
	$endswitch
	*dst = result;
}


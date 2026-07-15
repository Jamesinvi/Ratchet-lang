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
	LESS_EQ,
	GREATER,
	GREATER_EQ,
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
	Byte* 					globalMemory;
    HeapTracker 			trackedHeap;
    HeapTracker 			untrackedHeap;
    OutStream 				output;
    int 					frameCount;
	bool 					running;
	sz 						stackHead;
}

fn RunResult run(BCProgram* program, OutStream outStream)
{
	Vm vm = {};
    vm.init(program, outStream);
	return vm.execute_program();
}

fn void Vm.init(Vm* this, BCProgram* program, OutStream output)
{
    this.program = program;
    this.output = output;
	for(sz i = 0; i < STACK_MAX; i++){
		this.stack[i] = 0;
	}
}

fn RunResult Vm.execute_program(Vm* vm)
{
	if(vm.program.functions.len() == 0){
		return RunResult.OK;
	}
	vm.running = true;
	vm.functions = vm.program.functions.entries;
	vm.instructions = vm.program.instructions.entries;
	vm.blocks = vm.program.blocks.entries;

	vm.trackedHeap = {};
	vm.trackedHeap.init("tracked heap");

	vm.untrackedHeap = {};
	vm.untrackedHeap.init("untracked heap");
	if (vm.program.globalMemorySize > 0) {
		vm.globalMemory = (Byte*)vm.untrackedHeap.alloc((sz)vm.program.globalMemorySize, uptr::alignment);
		mem::copy(vm.globalMemory, vm.program.globalInitialData.entries, vm.program.globalInitialData.len(), 1, 1);
	}

	BCFunction* entry = &vm.functions[vm.program.entryFunctionIdx];
	BCBlock* entryBlock = &vm.blocks[entry.blocksStart];
	vm.instructionPtr =  &vm.instructions[entryBlock.instructionsStart];

	vm.frameCount = 1;
	vm.frame = &vm.frames[0];
	vm.frame.base = 0;
	vm.frame.size = entry.frameSize;
	vm.frame.callInfoIdx = -1;
	vm.stackHead = entry.frameSize;
	
	while(vm.running) {
		BCInstruction* inst = vm.instructionPtr;
		vm.instructionPtr++; 
		// log::logn("%s", inst.opCode.asStr);
		switch(inst.opCode)
		{
			case BCOpCode.NOP:		continue;

			// Special increment op to make ++ and +1 more explicit and optimizable
			case BCOpCode.INCREMENT:
				int* v = (int*)&vm.stack[vm.frame.base + inst.destOffset];
				*v  = (*v) + 1;

			// Initialize to 0
			case BCOpCode.ZERO_BYTES:				
				Byte* dst = (Byte*)&vm.stack[vm.frame.base + inst.destOffset];
				mem::set(dst, 0, inst.byteCount, 1);

			// Cast
			case BCOpCode.CAST:						vm.cast_op(inst);
		    // Const				
			case BCOpCode.CONSTI:					vm.const_op(inst, int);
			case BCOpCode.CONSTF:					vm.const_op(inst, float);
			case BCOpCode.CONSTD:					vm.const_op(inst, double);
			case BCOpCode.CONSTB:					vm.const_op(inst, bool);
			case BCOpCode.CONSTS:					vm.const_op(inst, StringIdx);
			// Less		
			case BCOpCode.LESSI:					vm.cmp_op(inst, int, VmCmpOp.LESS);
			case BCOpCode.LESSF:					vm.cmp_op(inst, float, VmCmpOp.LESS);
			case BCOpCode.LESSD:					vm.cmp_op(inst, double, VmCmpOp.LESS);
			case BCOpCode.LESSI_IM:					vm.cmp_op_immediate(inst, int, VmCmpOp.LESS);
			case BCOpCode.LESS_EQI:					vm.cmp_op(inst, int, VmCmpOp.LESS_EQ);
			case BCOpCode.LESS_EQF:					vm.cmp_op(inst, float, VmCmpOp.LESS_EQ);
			case BCOpCode.LESS_EQD:					vm.cmp_op(inst, double, VmCmpOp.LESS_EQ);
			// Greater		
			case BCOpCode.GREATERI:					vm.cmp_op(inst, int, VmCmpOp.GREATER);
			case BCOpCode.GREATERF:					vm.cmp_op(inst, float, VmCmpOp.GREATER);
			case BCOpCode.GREATERD:					vm.cmp_op(inst, double, VmCmpOp.GREATER);
			case BCOpCode.GREATER_EQI:				vm.cmp_op(inst, int, VmCmpOp.GREATER_EQ);
			case BCOpCode.GREATER_EQF:				vm.cmp_op(inst, float, VmCmpOp.GREATER_EQ);
			case BCOpCode.GREATER_EQD:				vm.cmp_op(inst, double, VmCmpOp.GREATER_EQ);
			// Equal		
			case BCOpCode.EQI:						vm.cmp_op(inst, int, VmCmpOp.EQ);
			case BCOpCode.EQF:						vm.cmp_op(inst, float, VmCmpOp.EQ);
			case BCOpCode.EQD:						vm.cmp_op(inst, double, VmCmpOp.EQ);
			case BCOpCode.EQB:						vm.cmp_op(inst, bool, VmCmpOp.EQ);
			// Not Equal		
			case BCOpCode.NEQI:						vm.cmp_op(inst, int, VmCmpOp.NEQ);
			case BCOpCode.NEQF:						vm.cmp_op(inst, float, VmCmpOp.NEQ);
			case BCOpCode.NEQD:						vm.cmp_op(inst, double, VmCmpOp.NEQ);
			case BCOpCode.NEQB:						vm.cmp_op(inst, bool, VmCmpOp.NEQ);
			// Logic		
			case BCOpCode.AND:						vm.cmp_op(inst, bool, VmCmpOp.AND);
			case BCOpCode.OR:						vm.cmp_op(inst, bool, VmCmpOp.OR);
			// Mov		
			case BCOpCode.MOVI:						vm.mov_op(inst, int);
			case BCOpCode.MOVF:						vm.mov_op(inst, float);
			case BCOpCode.MOVD:						vm.mov_op(inst, double);
			case BCOpCode.MOVB:						vm.mov_op(inst, bool);
			case BCOpCode.MOV_BYTES:				vm.mov_bytes(inst);
			case BCOpCode.MOV_REF:					vm.mov_op(inst, uptr);	// TODO: Managed-reference loads/stores need GC bookkeeping once GC exists
			case BCOpCode.LOAD_BORROW: 				vm.load_indirect(inst);
			case BCOpCode.LOAD_REF_VALUE:			vm.load_ref_value(inst);
			case BCOpCode.LOAD_REF_FIELD:			vm.load_indirect(inst);
			case BCOpCode.STORE_BORROW:				vm.store_indirect(inst);
			case BCOpCode.STORE_REF_VALUE:			vm.store_ref_value(inst);
			case BCOpCode.STORE_REF_FIELD:			vm.store_indirect(inst);

			// Globals. We could have typed opcodes, but for now, they're type-agnostic. Copy byte-by-byte
			case BCOpCode.LOAD_GLOBAL:				vm.load_global(inst);
			case BCOpCode.LOAD_GLOBAL_REF_VALUE: 	vm.load_global_ref_value(inst);
			case BCOpCode.STORE_GLOBAL:				vm.store_global(inst);
			case BCOpCode.STORE_GLOBAL_REF_VALUE:	vm.store_global_ref_value(inst);
			
			// Add
			case BCOpCode.ADDI:						vm.bin_math_op(inst, int, VmMathOp.ADD);
			case BCOpCode.ADDF:						vm.bin_math_op(inst, float, VmMathOp.ADD);
			case BCOpCode.ADDD:						vm.bin_math_op(inst, double, VmMathOp.ADD);
			case BCOpCode.ADDI_IM:					vm.bin_math_op_immediate(inst, int, VmMathOp.ADD);
			// Sub				
			case BCOpCode.SUBI:						vm.bin_math_op(inst, int, VmMathOp.SUB);
			case BCOpCode.SUBF:						vm.bin_math_op(inst, float, VmMathOp.SUB);
			case BCOpCode.SUBD:						vm.bin_math_op(inst, double, VmMathOp.SUB);
			// Mul				
			case BCOpCode.MULI:						vm.bin_math_op(inst, int, VmMathOp.MUL);
			case BCOpCode.MULF:						vm.bin_math_op(inst, float, VmMathOp.MUL);
			case BCOpCode.MULD:						vm.bin_math_op(inst, double, VmMathOp.MUL);
			// Div				
			case BCOpCode.DIVI:						vm.bin_math_op(inst, int, VmMathOp.DIV);
			case BCOpCode.DIVF:						vm.bin_math_op(inst, float, VmMathOp.DIV);
			case BCOpCode.DIVD:						vm.bin_math_op(inst, double, VmMathOp.DIV);
			// Echo				
			case BCOpCode.ECHOI:					vm.echo(inst, int);
			case BCOpCode.ECHOF:					vm.echo(inst, float);
			case BCOpCode.ECHOD:					vm.echo(inst, double);
			case BCOpCode.ECHOB:					vm.echo(inst, bool);
			case BCOpCode.ECHO_REF:					vm.echo(inst, uptr);
			case BCOpCode.ECHOS:					vm.echo_string(inst);
			
			// Allocation
			case BCOpCode.ALLOC_GC:					vm.alloc_gc(inst);
			// Control flow
			case BCOpCode.BRANCH_IF_FALSE:			vm.branch_if_false(inst);
            case BCOpCode.JUMP:						vm.jump(inst);
			case BCOpCode.CALL: 					vm.call(inst);
			case BCOpCode.RETURN:					vm.execute_return(inst);
			default:
				log::errlog("%s not currently supported", inst.opCode);
				return RunResult.RUNTIME_ERR;
		}
	} 

	// vm.print_stack();
	vm.trackedHeap.free();	
	vm.untrackedHeap.free();	
	return RunResult.OK;
}

macro Vm.echo(Vm* vm, BCInstruction* inst, $Type)
{
	// use the vm output stream. stdout by default
	$if $Type == uptr:
    	TypeInfo pointeeType = inst.typeInfo.pointee_type();
		switch (pointeeType.type)
		{
			case ValueType.INT:		vm.print_value_from_heap(inst.leftOffset, int);
			case ValueType.FLOAT:	vm.print_value_from_heap(inst.leftOffset, float);
			case ValueType.DOUBLE:	vm.print_value_from_heap(inst.leftOffset, double);
			case ValueType.BOOL:	vm.print_value_from_heap(inst.leftOffset, bool);
			default:				unreachable();
		}
	$else		
		$Type* val = ($Type*)&vm.stack[vm.frame.base + inst.leftOffset];
    	io::fprintfn(vm.output, "%s", *val);
	$endif
}

fn void Vm.echo_string(Vm* vm, BCInstruction* inst) @inline
{
	StringIdx* stringIdx = (StringIdx*)&vm.stack[vm.frame.base + inst.leftOffset];
	// use the vm output stream. stdout by default
	io::fprintfn(vm.output, "%s", vm.program.strings[*stringIdx]);
}

fn void Vm.load_indirect(Vm* vm, BCInstruction* inst) @inline
{
	Byte* src = (Byte*)vm.deref_indirect(inst.leftOffset) + inst.rightOffset;
	Byte* dst = &vm.stack[vm.frame.base + inst.destOffset];
	mem::copy(dst, src, inst.byteCount, 1, 1);
}

macro Vm.print_value_from_heap(Vm* vm, short offset, $Type)
{
	$Type* heapValuePtr = vm.deref_indirect(offset);
	io::fprintfn(vm.output, "%s", *heapValuePtr);
}

macro void* Vm.deref_indirect(Vm* vm, short offset)
{
	// Get the stack slot that contains the address of the indirect value
	uptr* refAddress = (uptr*)&vm.stack[vm.frame.base + offset];
	// Load the value at address. This is our pointer to the actual data.
	void* refValuePtr = (void*)*refAddress;
	// Outside this macro, it's possible to access the actual value by 
	// dereferencing using a type: int v = (int)*heapValuePtr;
	return refValuePtr;
}

fn void Vm.load_global(Vm* vm, BCInstruction* inst) @inline
{
	Byte* src = &vm.globalMemory[inst.leftOffset];
	Byte* dst = &vm.stack[vm.frame.base + inst.destOffset];
	mem::copy(dst, src, inst.byteCount, 1, 1);
}

fn void Vm.load_ref_value(Vm* vm, BCInstruction* inst) @inline
{
	Byte* refSlot;
	if (inst.rightOffset == runtime::NO_OFFSET) {
		refSlot = &vm.stack[vm.frame.base + inst.leftOffset];
	} else {
		refSlot = (Byte*)vm.deref_indirect(inst.leftOffset) + inst.rightOffset;
	}
	Byte* refValueSrc = (Byte*)*(uptr*)refSlot;
	Byte* refValueDst = &vm.stack[vm.frame.base + inst.destOffset];
	mem::copy(refValueDst, refValueSrc, inst.byteCount, 1, 1);
}

fn void Vm.load_global_ref_value(Vm* vm, BCInstruction* inst) @inline
{
	// This it to access the ".value" of a global ref variable. (int&)
	// There's an extra indirection because int& is already a reference,
	// so we need to get the value stored at the address pointed by the reference
	uptr* ptrToRefValue = (uptr*)&vm.globalMemory[inst.leftOffset];
	uptr refValue = *ptrToRefValue;
	Byte* refValueSrc = (Byte*)refValue;
	Byte* refValueDst = &vm.stack[vm.frame.base + inst.destOffset];
	mem::copy(refValueDst, refValueSrc, inst.byteCount, 1, 1);
}

fn void Vm.store_global_ref_value(Vm* vm, BCInstruction* inst) @inline
{
	// This it to store the ".value" of a global ref variable. (int&)
	// There's an extra indirection because int& is already a reference,
	// so we need to get the value stored at the address pointed by the reference
	uptr* ptrToRefValue = (uptr*)&vm.globalMemory[inst.destOffset];
	uptr refValue = *ptrToRefValue;
	Byte* refValueDst = (Byte*)refValue;
	Byte* refValueSrc = &vm.stack[vm.frame.base + inst.leftOffset];
	mem::copy(refValueDst, refValueSrc, inst.byteCount, 1, 1);
}

fn void Vm.store_ref_value(Vm* vm, BCInstruction* inst) @inline
{
	Byte* refSlot;
	if (inst.rightOffset == runtime::NO_OFFSET) {
		refSlot = &vm.stack[vm.frame.base + inst.destOffset];
	} else {
		refSlot = (Byte*)vm.deref_indirect(inst.destOffset) + inst.rightOffset;
	}
	Byte* refValueDst = (Byte*)*(uptr*)refSlot;
	Byte* refValueSrc = &vm.stack[vm.frame.base + inst.leftOffset];
	mem::copy(refValueDst, refValueSrc, inst.byteCount, 1, 1);
}

fn void Vm.store_global(Vm* vm, BCInstruction* inst) @inline
{
	Byte* dst = &vm.globalMemory[inst.destOffset];
	Byte* src = &vm.stack[vm.frame.base + inst.leftOffset];
	mem::copy(dst, src, inst.byteCount, 1, 1);
}

macro Vm.const_op(Vm* vm, BCInstruction* inst, $Type)
{
	$Type* dst = ($Type*)&vm.stack[vm.frame.base + inst.destOffset];
	$Type field;
	$switch $Type:
		$case int: 			field = inst.immInt;
		$case float: 		field = inst.immFloat;
		$case double: 		field = inst.immDouble;
		$case bool: 		field = inst.immBool;
		$case StringIdx: 	field = inst.immStringIdx;
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
		$case VmCmpOp.LESS_EQ: 	result = *left <= *right;
		$case VmCmpOp.GREATER: 	result = *left > *right;
		$case VmCmpOp.GREATER_EQ: result = *left >= *right;
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
		$case VmCmpOp.LESS_EQ: 	result = *left <= right;
		$case VmCmpOp.GREATER: 	result = *left > right;
		$case VmCmpOp.GREATER_EQ: result = *left >= right;
		$case VmCmpOp.AND: 		result = *left && right;
		$case VmCmpOp.OR: 		result = *left || right;
	$endswitch
	*dst = result;
}

fn void Vm.alloc_gc(Vm* vm, BCInstruction* inst)
{
	// Get information about the type we need to allocate
    TypeInfo pointeeType = inst.typeInfo.pointee_type();
    sz size = pointeeType.size();
    sz alignment = pointeeType.alignment();

	// src is the data we need to store at the allocated location
    Byte* src = &vm.stack[vm.frame.base + inst.leftOffset];
    void* allocated = vm.trackedHeap.alloc(size, alignment);
	// copy the src data into the newly allocated spot
    mem::copy(allocated, src, size, 1, 1);

	// Store the address to the newly allocated data into dest. 
	// This is what is moved around when copying an int& around
    uptr* dest = (uptr*)&vm.stack[vm.frame.base + inst.destOffset];
    *dest = (uptr)allocated;
}

fn void Vm.mov_bytes(Vm* vm, BCInstruction* inst) @inline
{
	Byte* dst = (Byte*)&vm.stack[vm.frame.base + inst.destOffset];
	Byte* src = (Byte*)&vm.stack[vm.frame.base + inst.leftOffset];
	// memmove handles overlapping memory correctly. memcpy is undefined
	mem::move(dst, src, inst.byteCount);
}

fn void Vm.store_indirect(Vm* vm, BCInstruction* inst) @inline
{
	Byte* dst = (Byte*)vm.deref_indirect(inst.destOffset) + inst.rightOffset;
	Byte* src = &vm.stack[vm.frame.base + inst.leftOffset];
	mem::copy(dst, src, inst.byteCount, 1, 1);
}

fn void Vm.cast_op(Vm* vm, BCInstruction* inst)
{
	switch(inst.castKind)
	{
		case BCCastKind.INT_TO_FLOAT: 		vm.cast_value(inst, int, float);
		case BCCastKind.INT_TO_DOUBLE: 		vm.cast_value(inst, int, double);
		case BCCastKind.FLOAT_TO_INT: 		vm.cast_value(inst, float, int);
		case BCCastKind.FLOAT_TO_DOUBLE: 	vm.cast_value(inst, float, double);
		case BCCastKind.DOUBLE_TO_INT:	 	vm.cast_value(inst, double, int);
		case BCCastKind.DOUBLE_TO_FLOAT: 	vm.cast_value(inst, double, float);
		case BCCastKind.IDENTITY: 			break;	//no_op
	}
}

macro Vm.cast_value(Vm* vm, BCInstruction* inst, $Source, $Target) {
    $Source* source = ($Source*)&vm.stack[vm.frame.base + inst.leftOffset];
    $Target* target = ($Target*)&vm.stack[vm.frame.base + inst.destOffset];
    *target = ($Target)*source;
}


fn void Vm.branch_if_false(Vm* vm, BCInstruction* inst) @inline
{
	bool* condition = (bool*)&vm.stack[vm.frame.base + inst.leftOffset];
	if(!*condition){
		BCBlock* block = &vm.blocks[inst.blockToJumpTo];
		vm.instructionPtr = &vm.instructions[(sz)block.instructionsStart]; 
	}
}

fn void Vm.jump(Vm* vm, BCInstruction* inst) @inline
{
	BCBlock* block = &vm.blocks[inst.blockToJumpTo];
	vm.instructionPtr = &vm.instructions[(sz)block.instructionsStart]; 
}

fn void Vm.call(Vm* vm, BCInstruction* inst)
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
	vm.frame.callInfoIdx = inst.callInfoIdx;
	vm.instructionPtr = &vm.instructions[vm.blocks[callee.blocksStart].instructionsStart];
	vm.frame.returnDestOffset = callInfo.returnDestOffset;
	vm.frame.returnSize = callInfo.returnSize;

	// Copy call arguments into the new stack frame
	for(int i = callInfo.argsStart; i < callInfo.argsEnd; i++){
		BCCallArg* arg = &vm.program.callArgs[i];
		Byte* dst = &vm.stack[vm.frame.base + arg.calleeOffset];
		if (arg.isBorrow) {
			// Borrow parameters receive the address of caller storage instead of a value copy.
			uptr address;
			if (arg.callerIsBorrow) {
				// The caller place is itself borrowed from another function, so its slot contains the
				// original address. Forward it instead of taking the slot's address.
				uptr* callerBorrow = (uptr*)&vm.stack[callerFrame.base + arg.callerOffset];
				address = *callerBorrow + (uptr)arg.projectionOffset;
			} else {
				// The caller owns the value in its stack frame; borrow that place directly. (copy the address of the caller's variable)
				address = (uptr)&vm.stack[callerFrame.base + arg.callerOffset + arg.projectionOffset];
			}
			// The callee's parameter slot stores the resulting borrow pointer.
			*(uptr*)dst = address;
		} else {
			// Simple pass-by-value case
			Byte* src = &vm.stack[callerFrame.base + arg.callerOffset];
			mem::copy(dst, src, (sz)arg.size, 1, 1);
		}
	}
}

fn void Vm.execute_return(Vm* vm, BCInstruction* inst)
{
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
		vm.stackHead = returnFrameBase;
		vm.frame = &vm.frames[vm.frameCount -1];
		if (returnSize > 0) {
			Byte* src = &vm.stack[returnFrameBase + returnSourceOffset];
			Byte* dest = &vm.stack[vm.frame.base + offset];
			mem::copy(dest, src, (sz)returnSize, 1, 1);
		}
		vm.instructionPtr = returnPtr;
	}
}

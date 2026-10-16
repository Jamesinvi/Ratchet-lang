module vm;
import common;
import std::time;
import std::math;

<*
 Argument convention for this function:
 Vm* vm, no args, out double result
*>
fn void clock(Vm* vm, NativeRuntimeCallArg[] arguments, NativeRuntimeCallArg[] results)
{
	if (!validate_arguments(vm, arguments))
	{
		// Trap here
		return;
	}
	double* resultStorage = (double*)results[0].data;
	double resultValue    = (double)std::time::os::native_clock();
	*resultStorage = resultValue;
}


<*
 Argument convention for this function:
 Vm* vm, float input, out float result
*>
fn void float_sqrt(Vm* vm, NativeRuntimeCallArg[] arguments, NativeRuntimeCallArg[] results)
{
	if (!validate_arguments(vm, arguments))
	{
		// Trap here
		return;
	}
	float input          = *(float*)arguments[0].data;
	float* resultStorage = (float*)results[0].data;
	float resultValue    = math::sqrt(input);
	*resultStorage = resultValue;
}


<*
 Argument convention for this function:
 Vm* vm, ArrayHandle* handle, utpr toAdd, no results
*>
fn void array_append(Vm* vm, NativeRuntimeCallArg[] arguments, NativeRuntimeCallArg[] results)
{
	if (!validate_arguments(vm, arguments))
	{
		// Trap here
		return;
	}
	ArrayHandle* handle = *(ArrayHandle**)arguments[0].data;
	void* toAdd         = arguments[1].data;
	TypeInfo toAddType  = arguments[0].type;
	if (handle.length >= handle.capacity)
	{
		vm.trackedHeap.realloc_array(handle, toAddType);
	}
	int index          = handle.length;
	Byte* bufferAsData = (Byte*)handle.buffer;
	mem::copy(&bufferAsData[index * arguments[1].type.size()], toAdd, arguments[1].type.size());
	handle.length++;
}

macro bool validate_arguments(Vm* vm, NativeRuntimeCallArg[] arguments)
{
	return true;
}


module common;
import vm;

alias NativeFn = fn void(Vm* vm, NativeRuntimeCallArg[] arguments, NativeRuntimeCallArg[] results);


struct NativeRuntimeCallArg
{
	TypeInfo type;
	void* data;
}

struct NativeCall
{
	String name;
	NativeFn function;
	CallTargetKind targetKind;
	TypeInfo returnType;
	FunctionParameter[] params;
}

// c3fmt off
NativeCall[] nativeFunctions =
{
	{
		// clock
		.name 			= "clock",
		.function 		= (NativeFn)&vm::clock,
		.targetKind 	= CallTargetKind.NATIVE_FUN,
		. returnType 	= common::make_type(ValueType.DOUBLE),
		.params 		= { }
		},
	{
		// sqrtf
		.name = "sqrtf",
		.function   	= (NativeFn)&vm::float_sqrt,
		.targetKind 	= CallTargetKind.NATIVE_FUN,
		. returnType 	= common::make_type(ValueType.FLOAT),
		.params =
		{
			{
				.type 		= common::make_type(ValueType.FLOAT),
				.passMode 	= ParamPassMode.VALUE
			}
		}
	},
};
// c3fmt on


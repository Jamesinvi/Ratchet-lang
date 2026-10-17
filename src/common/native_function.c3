module common;
import vm;

alias NativeFn = fn void(Vm* vm, NativeRuntimeCallArg[] arguments, NativeRuntimeCallArg[] results);
alias NativeMethod = fn void(Vm* vm, NativeRuntimeCallArg[] arguments, NativeRuntimeCallArg[] results);


struct NativeRuntimeCallArg
{
	TypeInfo type;
	void* data;
}

struct NativeCall
{
	String name;
	union
	{
		NativeFn function;
		NativeFn method;
	}
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
		.returnType 	= common::make_type(ValueType.DOUBLE),
		.params 		= { }
	},
	{
		// sqrtf
		.name = "sqrtf",
		.function   	= (NativeFn)&vm::float_sqrt,
		.targetKind 	= CallTargetKind.NATIVE_FUN,
		.returnType 	= common::make_type(ValueType.FLOAT),
		.params =
		{
			{
				.type 		= common::make_type(ValueType.FLOAT),
				.passMode 	= ParamPassMode.VALUE
			}
		}
	},
	{
		// array_append
		.name 			= "add",
		.method 		= (NativeMethod)&vm::array_append,
		.targetKind 	= CallTargetKind.NATIVE_METHOD,
		.returnType 	= common::make_type(ValueType.NULL),
		.params 		= 
		{
			{
				.type = common::make_type(ValueType.ARR_REF_GC), 
				.passMode = ParamPassMode.INOUT,
				.flags = FunctionParameterFlags.PARAMETER_TYPE_MATCHES_RECEIVER
			},
			{
				.type = common::make_type(ValueType.NULL), 
				.passMode = ParamPassMode.VALUE,
				.flags = FunctionParameterFlags.PARAMETER_TYPE_MATCHES_RECEIVER_ELEMENT
			}
		},
	},
};
// c3fmt on


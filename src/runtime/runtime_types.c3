module runtime;
import compiler::parser;


struct StackFrame
{
	BCFunction function;
	sz base;
}
module vm;
import common;
import runtime;

struct StackFrame
{
	sz base;
	BCInstruction* returnPtr;
	short returnDestOffset;
 	short returnSize;
	short size;
}
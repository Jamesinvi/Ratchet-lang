module vm;
import common;
import runtime;

struct StackFrame
{
	sz base;
	BCInstruction* returnPtr;
	BCCallInfoIdx callInfoIdx;
	short returnDestOffset;
 	short returnSize;
	short size;
}

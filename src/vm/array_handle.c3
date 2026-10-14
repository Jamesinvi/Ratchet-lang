module vm::memory;
import common;

struct ArrayHandle
{
	int length;
	int capacity;
	void* buffer;
}


enum HeapAllocationKind
{
	ARRAY,
	VALUE,
}

struct HeapAllocation
{
	uptr ptr;
	TypeInfo type;
	HeapAllocationKind kind;
}


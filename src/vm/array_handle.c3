module vm::memory;


struct ArrayHandle
{
	int length;
	int capacity;
	void* buffer;
}


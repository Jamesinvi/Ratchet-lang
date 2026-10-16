module vm::memory;
import common;
import runtime;
import globals;
import log;
import std::core;
import std::core::mem;
import std::math;
import std::collections;

<*
 Minimm threshold used to determine if GC must run, in bytes
 32 << 20 is 32 MB
 16 << 20 is 16 MB
 At runtime, the calculation is:
 nextGcHeapThreshold = sizeAtLastGc + max(GC_HEAP_MINIMUM_HEADROOM, sizeAtLastGc)
*>
const sz GC_HEAP_MINIMUM_HEADROOM = 32 << 20;

struct HeapTracker
{
	sz size;
	sz sizeAtLastGc;
	sz nextGcHeapThreshold;
	Allocator memory;
	List{HeapAllocation} allocations;
	HashMap{uptr, sz} allocationPositions;
	GrowableBitSet{ulong} marked;
}

fn void HeapTracker.init(HeapTracker* this, String name)
{
	this.size = 0;
	this.memory = mem;
	this.allocations.init(this.memory);
	this.marked.init(this.memory);
	this.allocationPositions.init(this.memory);
	this.nextGcHeapThreshold = GC_HEAP_MINIMUM_HEADROOM;
}

fn void HeapTracker.free(HeapTracker* this)
{
	foreach (&allocation : this.allocations)
	{
		if (allocation.kind == HeapAllocationKind.ARRAY)
		{
			ArrayHandle* arrayHandle = (ArrayHandle*)(allocation.ptr);
			free(arrayHandle.buffer);
		}
		free((void*)allocation.ptr);
	}
	this.allocations.free();
	this.marked.free();
	this.allocationPositions.free();
	this.size = 0;
}

fn void HeapTracker.track_alloc(HeapTracker* this, void* memory, TypeInfo* type, HeapAllocationKind allocKind)
{
	HeapAllocation allocation = { .ptr = (uptr)memory, .type = *type, .kind = allocKind };
	this.allocations.push(allocation);
	this.allocationPositions[(uptr)memory] = this.allocations.len() - 1;
}

fn void* HeapTracker.alloc(HeapTracker* this, TypeInfo typeToAllocate)
{
	int size              = typeToAllocate.size();
	int alignment         = typeToAllocate.alignment();
	void* allocatedMemory = this.alloc_raw(size, alignment);
	this.track_alloc(allocatedMemory, &typeToAllocate, HeapAllocationKind.VALUE);
	return allocatedMemory;
}

fn ArrayHandle* HeapTracker.alloc_array(HeapTracker* this, TypeInfoIdx typeInfoIdx, List{TypeInfo}* typeInfoTable, TypeInfo* arrayType, int arrayLen)
{
	TypeInfo elementType = arrayType.element_type();
	int elementSize      = elementType.size();
	int alignment        = elementType.alignment();
	int capacity         = math::next_power_of_2(arrayLen);
	// Allocate the handle using our allocator
	ArrayHandle* result  = (ArrayHandle*)this.alloc_raw(ArrayHandle::size, ArrayHandle::alignment);
	result.length = arrayLen;
	result.capacity = capacity;
	sz bufferSize = (sz)elementSize * capacity;
	// Allocate the buffer and set the handle's buffer to it
	result.buffer = this.alloc_raw(bufferSize, alignment);
	this.track_alloc((void*)result, &elementType, HeapAllocationKind.ARRAY);
	return result;
}

fn void HeapTracker.realloc_array(HeapTracker* this, ArrayHandle* handle, TypeInfo arrayType)
{
	TypeInfo elementType = arrayType.element_type();
	int elementSize      = elementType.size();
	int alignment        = elementType.alignment();
	// Allocate the handle using our allocator
	void* oldBuffer      = handle.buffer;
	sz oldAllocSize      = handle.capacity;
	handle.buffer = this.alloc_raw((sz)handle.capacity * 2 * elementSize, alignment);
	mem::copy(handle.buffer, oldBuffer, (sz)handle.length * elementSize);
	handle.capacity *= 2;
	free(oldBuffer);
	this.size -= oldAllocSize * elementSize;
}


fn void* HeapTracker.alloc_raw(HeapTracker* this, sz size, int alignment)
{
	this.size += size;
	return this.memory.acquire(size, AllocInitType.ZERO, alignment)!!;
}


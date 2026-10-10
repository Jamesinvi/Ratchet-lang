module vm::memory;
import common;
import std::collections;
import log;
import std::core;
import std::math;

struct HeapTracker
{
	sz sizeInBytes;
	DynamicArenaAllocator memory;
	List{ArrayHandle*} arrays;
}

fn void HeapTracker.init(HeapTracker* this, String name)
{
	this.sizeInBytes = 32 * 1024;
	this.memory = { };
	this.memory.init(mem, this.sizeInBytes);
	this.arrays.init(&this.memory);
}

fn void HeapTracker.free(HeapTracker* this)
{
	this.sizeInBytes = 0;
	this.memory.free();
}

fn void HeapTracker.track_alloc(HeapTracker* this)
{
}

fn void* HeapTracker.alloc(HeapTracker* this, sz size, sz alignment)
{
	return this.memory.acquire(size, AllocInitType.ZERO, alignment)!!;
}

fn ArrayHandle* HeapTracker.alloc_array(HeapTracker* this, sz elementSize, sz alignment, int length)
{
	int capacity        = math::next_power_of_2(length);
	// Allocate the handle using our allocator
	ArrayHandle* result = (ArrayHandle*)this.alloc(ArrayHandle::size, ArrayHandle::alignment);
	result.length = length;
	result.capacity = capacity;
	// Allocate the buffer and set the handle's buffer to it
	result.buffer = this.memory.acquire(elementSize * capacity, AllocInitType.ZERO, alignment)!!;
	this.arrays.push(result);
	return result;
}


fn void HeapTracker.release_obj(HeapTracker* this)
{
}

fn void HeapTracker.retain_obj(HeapTracker* thisj)
{
}

fn void HeapTracker.debug_print(HeapTracker* this)
{
}


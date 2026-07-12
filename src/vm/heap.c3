module vm::memory;
import common;
import std::collections;
import log;
import std::core::mem::alloc;
import std::core::mem::allocators;
struct HeapTracker
{
	sz sizeInBytes;
	DynamicArenaAllocator memory;
}

fn void HeapTracker.init(HeapTracker* this, String name){
	this.sizeInBytes = 32 * 1024;
	this.memory = {};
	this.memory.init(mem, this.sizeInBytes);
}

fn void HeapTracker.free(HeapTracker* this){
	this.sizeInBytes = 0;
	this.memory.free();
}

fn void HeapTracker.track_alloc(HeapTracker* this){
}

fn void* HeapTracker.alloc(HeapTracker* this, sz size, sz alignment){
	return this.memory.acquire(size, AllocInitType.ZERO, alignment)!!;
}


fn void HeapTracker.release_obj(HeapTracker* this){
}

fn void HeapTracker.retain_obj(HeapTracker* thisj){
}

fn void HeapTracker.debug_print(HeapTracker* this) {
}
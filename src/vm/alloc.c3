module vm::memory;
import common;
import std::collections;
import log;
import std::core::mem::alloc;
alias FreeSlotsStack = common::stack::Stack{sz};

struct HeapTracker
{
	int placeholder;
}

fn void HeapTracker.init(HeapTracker* this, String name){
}

fn void HeapTracker.free(HeapTracker* this){
}

fn void HeapTracker.track_alloc(HeapTracker* this){
}

fn void* HeapTracker.alloc(HeapTracker* this, sz size){
	return null;
}


fn void HeapTracker.release_obj(HeapTracker* this){
}

fn void HeapTracker.retain_obj(HeapTracker* thisj){
}

fn void HeapTracker.debug_print(HeapTracker* this) {
}
module vm::memory;
import common;
import std::collections;
import log;
import std::core::mem::alloc;
alias FreeSlotsStack = common::stack::Stack{sz};

struct HeapTracker
{
    List{Obj*} objects;
    HashSet{sz} usedSlots;
    FreeSlotsStack freeSlots;
    String name;
    TrackingAllocator allocator;
}

fn void HeapTracker.init(HeapTracker* this, String name){
    this.objects.init(mem);
    this.usedSlots.init(mem);
    this.freeSlots={};
    this.name = name;
    this.allocator = {};
    this.allocator.init(mem);
}

fn void HeapTracker.free(HeapTracker* this){
    foreach(obj : this.objects){
        if(obj.type == ObjType.FUNCTION){
            ((ObjFunction*)obj).deinit();
            free(((ObjFunction*)obj));
        }else if (obj.type == ObjType.STRING){
            ((ObjString*)obj).str.free(mem);
            free(((ObjString*)obj));
        }else if (obj.type == ObjType.NATIVE_FUNCTION){
            free(((ObjNative*)obj));
        }
    }
    this.objects.free();
    this.usedSlots.free();
    this.allocator.free();
}

fn void HeapTracker.track_alloc(HeapTracker* this, Obj* trackedObj){
    sz allocIndex = trackedObj.allocIndex;
    if(allocIndex!= common::UNTRACKED_ALLOC && this.usedSlots.contains(allocIndex) ){
        return;
    }

    sz index = 0;
    if(this.freeSlots.size == 0){
        index = this.objects.size;
        this.objects.push(trackedObj);
        this.usedSlots.add(index);
    }else{
        index = this.freeSlots.pop();
        this.objects[index] = trackedObj;
    }
    trackedObj.allocIndex = index;
}

fn void* HeapTracker.alloc(HeapTracker* this, sz size){
    return alloc::calloc(&this.allocator, size);
}


fn void HeapTracker.release_obj(HeapTracker* this, Obj* trackedObj){
    if(trackedObj.isConstant){
        return;
    }
    trackedObj.refCounter--;
}

fn void HeapTracker.retain_obj(HeapTracker* this, Obj* trackedObj){
    if(trackedObj.allocIndex==common::UNTRACKED_ALLOC){
        this.track_alloc(trackedObj);
    }
    trackedObj.refCounter++;
}

fn void HeapTracker.debug_print(HeapTracker* this) {
    log::logn("===========%s===========", this.name);
    foreach (idx, potentialSlot : this.objects){
        if(this.usedSlots.contains(idx)){
            this.objects[idx].debug_print();
        }
    }
    log::logn("===========END============");

}
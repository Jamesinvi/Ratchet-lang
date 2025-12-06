module vm::memory;
import common;
import std::io;
import std::collections;
alias FreeSlotsStack = common::stack::Stack{ulong};

struct HeapTracker (DebugPrintable)
{
    List{Obj*} objects;
    HashSet{ulong} usedSlots;
    FreeSlotsStack freeSlots;
    String name;
}

fn void HeapTracker.init(HeapTracker* this, String name){
    this.objects.init(mem);
    this.usedSlots.init(mem);
    this.freeSlots={};
    this.name = name;
}

fn void HeapTracker.free(HeapTracker* this){
    this.objects.free();
    this.usedSlots.free();
}

fn void HeapTracker.track_alloc(HeapTracker* this, Obj* trackedObj){
    ulong allocIndex = trackedObj.allocIndex;
    if(allocIndex!= ulong.max && this.usedSlots.contains(allocIndex) ){
        return;
    }

    ulong index = 0;
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

fn void HeapTracker.release_obj(HeapTracker* this, Obj* trackedObj){
    if(trackedObj.isConstant){
        return;
    }
    trackedObj.refCounter--;
}

fn void HeapTracker.retain_obj(HeapTracker* this, Obj* trackedObj){
    if(trackedObj.allocIndex==ulong.max){
        this.track_alloc(trackedObj);
    }
    trackedObj.refCounter++;
}

fn void HeapTracker.debug_print(HeapTracker* this) @dynamic {
    io::printfn("===========%s===========", this.name);
    foreach (idx, potentialSlot : this.objects){
        if(this.usedSlots.contains(idx)){
            this.objects[idx].debug_print();
        }
    }
    io::printfn("===========END============");

}
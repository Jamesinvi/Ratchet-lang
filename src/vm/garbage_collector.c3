module vm::memory;
import common;
import runtime;
import globals;
import log;
import std::core;
import std::core::mem;
import std::collections;
import std::math;


fn void HeapTracker.run_gc_if_necessary(HeapTracker* this, Byte[] stackRoots, Byte[] globalRoots) @inline
{
	if (this.size < this.nextGcHeapThreshold) return;
	this.run_gc(stackRoots, globalRoots);
}


<*
 Runs the garbage collector. Uses Mark-and-Sweep algorithm using DFS
*>
fn void HeapTracker.run_gc(HeapTracker* this, Byte[] stackRoots, Byte[] globalRoots)
{
	sz previousSizeAtLastGc = this.sizeAtLastGc;
	sz previousSize         = this.size;

	// Mark
	@pool()
	{
		List{sz} worklist = { };
		worklist.tinit(64);

		this.marked.data.clear();
		this.discover_roots(stackRoots, &worklist);
		this.discover_roots(globalRoots, &worklist);

		while (worklist.len() > 0)
		{
			sz allocationIdx           = worklist.pop()!!;
			HeapAllocation* allocation = &this.allocations[allocationIdx];
			this.mark_at_address(allocation.ptr, &allocation.type, &worklist, allocation.kind);
		}
	};

	// Sweep
	for (sz i = this.allocations.len() - 1; i >= 0; i--)
	{
		if (!this.marked.get(i))
		{
			if (this.allocations[i].kind == HeapAllocationKind.VALUE)
			{
				void* memoryToFree = (void*)this.allocations[i].ptr;
				free(memoryToFree);
				this.size -= this.allocations[i].type.size();
			}

			if (this.allocations[i].kind == HeapAllocationKind.ARRAY)
			{
				ArrayHandle* arrayHandle = (ArrayHandle*)this.allocations[i].ptr;
				free(arrayHandle.buffer);
				int arrayElementSize = this.allocations[i].type.size();
				this.size -= (sz)arrayHandle.capacity * arrayElementSize;
				free(arrayHandle);
				this.size -= ArrayHandle::size;
			}
			this.allocationPositions.remove(this.allocations[i].ptr);
			this.allocations.remove_unordered_at(i);
			if (i < this.allocations.len())
			{
				this.allocationPositions[this.allocations[i].ptr] = i;
			}
		}
	}
	// Cleanup/stats
	this.marked.data.clear();
	this.sizeAtLastGc = this.size;
	log::logn("heap: before: %.2f MiB | after: %.2f MiB", (double)previousSize / 1048576.0, (double)this.size / 1048576.0);
	this.nextGcHeapThreshold = this.sizeAtLastGc + math::max(GC_HEAP_MINIMUM_HEADROOM, this.sizeAtLastGc);
}

<*
 This function uses DFS (depth first search), to look at nested types and find data that is now garbage
 Traces managed references in value storage and queues their targets.
 For ARRAY allocations, address is the handle and typeInfo describes its elements.
*>
fn void HeapTracker.mark_at_address(HeapTracker* this, uptr address, TypeInfo* typeInfo, List{sz}* worklist, HeapAllocationKind kind = HeapAllocationKind.VALUE)
{
	// Heap arrays will call this function on all the elements of the array
	if (kind == HeapAllocationKind.ARRAY)
	{
		// If it's a heap array of builtin value types (like int[]&) we don't need to check anything
		// we know ints don't contain references
		if (typeInfo.is_builtin()) return;
		ArrayHandle* handle = (ArrayHandle*)address;
		sz elementSize      = typeInfo.size();
		for (int index = 0; index < handle.length; index++)
		{
			uptr elementAddress = (uptr)handle.buffer + (uptr)(index * elementSize);
			this.mark_at_address(elementAddress, typeInfo, worklist);
		}
		return;
	}

	// address points to value storage; only managed references contain a GC target.
	switch (typeInfo.type)
	{
		case ValueType.REF: nextcase;
		case ValueType.ARR_REF_GC:
			uptr target;
			mem::copy(&target, (void*)address, uptr::size, 1, 1);
			this.mark_and_enqueue(target, worklist);
			return;
		case ValueType.STRUCT:
			// Structs call this function on all fields, so that any REF are marked (recursively)
			CompStructTypeInfo* info = &globals::structTypes[typeInfo.structTypeIndex];
			foreach (&field : info.fieldInfos)
			{
				this.mark_at_address(address + field.offset, &field.typeInfo, worklist);
			}
			return;
		case ValueType.ARR_INLINE:
			TypeInfo elementType = typeInfo.element_type();
			if (elementType.is_builtin()) return;
			sz elementSize = elementType.size();
			for (int i = 0; i < typeInfo.arraySize; i++)
			{
				this.mark_at_address(address + (uptr)((sz)i * elementSize), &elementType, worklist);
			}
			return;
		case ValueType.NULL: nextcase;
		case ValueType.INT: nextcase;
		case ValueType.FLOAT: nextcase;
		case ValueType.DOUBLE: nextcase;
		case ValueType.BOOL: nextcase;
		case ValueType.STRING_LITERAL: nextcase;
		case ValueType.PTR: nextcase;
		case ValueType.ARR_REF_NOGC: nextcase;
		default: return;
	}
}

<*
 Scans the provided array for pointers to allocations
*>
fn void HeapTracker.discover_roots(HeapTracker* this, Byte[] toScan, List{sz}* worklist)
{
	for (sz offset = 0; offset + uptr::size <= toScan.len; offset += uptr::size)
	{
		uptr candidate;
		mem::copy(&candidate, &toScan[offset], uptr::size, 1, 1);
		this.mark_and_enqueue(candidate, worklist);
	}
}

fn void HeapTracker.mark_and_enqueue(HeapTracker* this, uptr address, List{sz}* worklist)
{
	if (address == 0) return;

	sz? allocationIdx = this.allocationPositions[address];
	if (catch err = allocationIdx) return;
	if (this.marked.get(allocationIdx)) return;

	this.marked.set(allocationIdx);
	worklist.push(allocationIdx);
}


module common::fixed_stack {Type};
import std::io;

const MAX_SIZE = 512;

struct FixedStack
{
    int size;
    Type[MAX_SIZE] items;
}

fn void FixedStack.push(FixedStack* this, Type element) @inline
{
    this.items[this.size++] = element;
}

fn void FixedStack.reset(FixedStack* this) @inline
{
    this.size = 0;
}

fn Type FixedStack.pop_val(FixedStack* this) @inline
{
    assert(this.size > 0);
    return this.items[--this.size];
}

fn Type* FixedStack.pop_ref(FixedStack* this) @inline
{
    assert(this.size > 0);
    return &this.items[--this.size];
}

fn Type FixedStack.peek(FixedStack* this) @inline
{
    return this.items[this.size-1];
}

fn Type* FixedStack.peek_ref(FixedStack* this) @inline
{
    return &this.items[this.size-1];
}

// 0 is top of the stack, 1 is one slot below, and so on
fn Type FixedStack.peek_at(FixedStack* this, int distance) @inline
{
    return this.items[this.size-1-distance];
}

// 0 is top of the stack, 1 is one slot below, and so on
fn Type* FixedStack.peek_at_ref(FixedStack* this, int distance) @inline
{
    return &this.items[this.size-1-distance];
}


fn bool FixedStack.is_empty(FixedStack* this) @inline
{
    return !this.size;
}


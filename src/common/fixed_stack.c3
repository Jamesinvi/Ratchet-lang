module common::fixed_stack {Type};
import std::io;

const MAX_SIZE = 512;

struct FixedStack
{
    int size;
    Type[MAX_SIZE] items;
}

fn void FixedStack.push(FixedStack* this, Type element)
{
    this.items[this.size++] = element;
}

fn void FixedStack.reset(FixedStack* this)
{
    this.size = 0;
}

fn Type FixedStack.pop(FixedStack* this)
{
    assert(this.size > 0);
    return this.items[--this.size];
}

fn Type* FixedStack.pop_ref(FixedStack* this)
{
    return &this.items[--this.size];
}

fn Type FixedStack.peek(FixedStack* this)
{
    return this.items[this.size-1];
}

fn Type FixedStack.peek_at(FixedStack* this, int distance)
{
    return this.items[this.size-1-distance];
}


fn bool FixedStack.is_empty(FixedStack* this)
{
    return !this.size;
}


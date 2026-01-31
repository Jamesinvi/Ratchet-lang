module common::stack <Type>;
struct Stack
{
    int capacity;
    int size;
    Type* items;
}

fn void Stack.push(Stack* this, Type element) @inline
{
    if (this.capacity == this.size)
    {
        this.capacity = this.capacity ? this.capacity * 2 : 16;
        this.items = realloc(this.items, Type.sizeof * this.capacity);
    }
    this.items[this.size++] = element;
}

fn void Stack.free(Stack* this) @inline
{
    free(this.items);
}

fn void Stack.reset(Stack* this) @inline
{
    this.size = 0;
    this.capacity = 0;
}

fn Type Stack.pop(Stack* this) @inline
{
    assert(this.size > 0);
    return this.items[--this.size];
}

fn Type* Stack.pop_ref(Stack* this) @inline
{
    return &this.items[--this.size];
}

fn Type Stack.peek(Stack* this) @inline
{
    return this.items[this.size-1];
}

fn Type Stack.peek_at(Stack* this, int distance) @inline
{
    return this.items[this.size-1-distance];
}

fn bool Stack.is_empty(Stack* this)
{
    return !this.size;
}


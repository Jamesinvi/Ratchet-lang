# Ratchet Language

**Ratchet** is a small, imperative, strongly typed language with familiar C-like syntax.

The goal is to keep the language small but powerful.

The language is designed for tooling and scripting while keeping a strong type system and compile-time checks. It has a GC but the runtime is very different from a standard "GC-ed" language.

Ratchet is built around two ideas:

1. **Explicit memory shape** — values, managed references, manual pointers, and borrows are distinct and visible in the type system.
2. **Explicit time flow** — long-running behavior can be written with `coroutine` declarations and controlled `wait` points.

Storage and lifetime choices are explicit **per variable**. Instead of hiding allocation behavior behind runtime defaults, Ratchet makes it visible in types so you can reason about where data lives and make less mistakes.

At a high level:

1. `T` is a **stack-allocated value**.
2. `T&` is a **GC-tracked heap-allocated reference**.
3. `T*` is a **non-GC heap-allocated reference** with manual lifetime.

This model lets you start with straightforward code, then selectively move specific values to GC-tracked or manual heap storage only where performance and allocation behavior matters.

Ratchet is still being actively built and is **not fully working yet**. The current implementation is moving toward a typed register-based VM. Older proof-of-concept releases may not match the design described here.

The runtime direction is interpreted execution first, with a planned **JIT** and a possible optional **AOT** path later.

## Sections

1. [Design Goals](#design-goals)
2. [Syntax Basics](#syntax-basixcs)
3. [Types](#types)
4. [Functions](#functions)
5. [Values, References, and Pointers](#values-references-and-pointers)
6. [Structs and Methods](#structs-and-methods)
7. [Arrays](#arrays)
8. [Coroutines](#coroutines)
9. [Borrow Parameters](#borrow-parameters)
10. [Examples](#examples)
11. [Current Status](#current-status)

<a id="design-goals" name="design-goals"></a>
## Design Goals

1. Keep the language **small**, clear, and easy to embed.
2. Keep everyday code simple with **value semantics**.
3. Keep memory behavior explicit in types, so storage and ownership are visible at a glance.
4. Allow explicit control where allocation strategy, lifetime, and runtime behavior matter.
5. Support long-running stateful behavior without having to create state machines for everything.

<a id="syntax-basics" name="syntax-basics"></a>
## Syntax Basics

Ratchet uses familiar C-like structure.

1. Programs are built from declarations such as `fn`, `coroutine`, and `struct`.
2. Statements end with `;`.
3. Blocks use `{ ... }`.
4. Variables use `Type name = expression;`.

Quick look:

```cpp
int score = 42;
if (score > 10) {
    echo score;
}
```

<a id="types" name="types"></a>
## Types

### Primitive types

1. `bool`
2. `int`
3. `float`
4. `double`
5. `null` for no-return function signatures

### String literals

String literals such as `"hello"` are compile-time constants, not values of a
built-in `string` type. In the current executable subset, string literals can be
printed directly with `echo`. A general-purpose `String` type is intended to be
provided by the standard library.

### User types

1. `struct` value types
2. `T&` managed heap references
3. `T*` manually managed/native pointers
4. Array forms such as `T[N]`, `T[]&`, and `T[]*`

<a id="functions" name="functions"></a>
## Functions

Functions run immediately and complete before returning. A normal `fn` cannot suspend.

One complete function example:

```cpp
fn int clamp(int value, int minV, int maxV) {
    if (value < minV) {
        return minV;
    }
    if (value > maxV) {
        return maxV;
    }
    return value;
}

fn bool program() {
    int raw = 120;
    int safe = clamp(raw, 0, 100);
    echo safe;
    return true;
}
```

General shape:

```cpp
fn <return-type> <name>(<typed-params>) {
    // body
}
```

Notes:

1. `null` is used for functions that do not return a value.
2. Parameters are passed by value unless they use reference, pointer, or borrow forms.
3. `wait` is not legal inside a normal function.


<a id="values-references-and-pointers" name="values-references-and-pointers"></a>
## Values, References, and Pointers

Ratchet makes storage mode explicit in type spelling.

| Form | Meaning | Allocation | Copy behavior |
| --- | --- | --- | --- |
| `T` | Value type | Stack/inline by default | Full value copy |
| `T&` | Managed heap reference | `new T&` | Reference copy |
| `T*` | Manual/native pointer | `new T*` | Pointer copy |

Quick examples:

```cpp
int a = 5;                  // value
int& b = new int& { 5 };    // managed heap reference
int* c = new int* { 5 };    // manual/native pointer
free(c);
```

Notes:

1. `T`, `T&`, and `T*` are distinct and not implicitly convertible.
2. `T&` participates in Ratchet's managed runtime.
3. `T*` is for manual/native ownership boundaries and must be handled explicitly.

### Managed reference assignment

Managed references are rebindable. Assigning one `T&` to another changes which
managed object the destination references; it does not copy the referenced
value. Assigning a plain `T` directly to a `T&` is not allowed.

Managed references to primitive values expose a built-in `.value` property for
reading and mutation:

```cpp
int& first = new int& { 5 };
int& second = new int& { 12 };

first = second;       // Rebind first to the same managed integer as second.
first.value = 20;     // Mutate the shared integer.
echo second.value;    // 20

// first = 12;        // Invalid: int cannot be assigned to int&.
```

The `.value` property applies to managed references to primitive values such as
`int&`, `float&`, `double&`, and `bool&`. Managed references to structs access
the struct's fields normally, such as `enemy.hp`.

Equality between managed references compares object identity. To compare the
contents of primitive references, compare their `.value` properties instead.

<a id="coroutines" name="coroutines"></a>
## Coroutines

A `coroutine` is a named resumable procedure. It is used for behavior that unfolds over time.

A coroutine is **not** a function value and it is controlled through a CoroutineHandle. Operations like starting/canceling the coroutine are done with the handle.

Example:

```cpp
coroutine regen(Enemy& enemy, float amount) {
    while (enemy.alive) {
        enemy.hp = enemy.hp + amount;
        wait seconds(1.0f);
    }

    echo "regen stopped";
}

fn bool program() {
    Enemy& enemy = new Enemy&();
    enemy.hp = 0;
    CoroutineHandle h = start_co regen(enemy, 5.0f);

    // Other code ...

    stop_coroutine(h);
    // if the program ran for long enough, regen will have regenerated some health.
    return enemy.hp == 0; // should return true only if the coroutine didn't run properly
}
```

Allowed `wait` forms are intentionally controlled by the language/runtime. Planned forms include:

```cpp
wait seconds(1.0f);
wait until (self.hp < 50);
wait event TickEvent as tick;
```

Coroutine rules:

1. `wait` is only legal inside a `coroutine`.
2. A `coroutine` cannot be called like a normal function.
3. Starting a `coroutine` creates a `CoroutineHandle`, used to control scheduling.
4. A `coroutine` cannot directly wait for another coroutine to finish.
5. Coroutines may be spawned explicitly by the host/runtime.
6. Borrowed values such as `in` and `inout` parameters must not escape across a `wait` point.

This keeps coroutines powerful but predictable: they model explicit time flow without allowing arbitrary coroutine composition or hidden waits that make program flow hard to reason about.

`defer` is planned later so cleanup can run when a coroutine finishes or is cancelled.

<a id="arrays" name="arrays"></a>
## Arrays

Array forms using `Vec2`:

```cpp
Vec2[4] a = Vec2[4];          // stack-allocated array, size must be known at compile time
Vec2[]& c = new Vec2[4]&;     // GC-tracked array reference
Vec2[]* d = new Vec2[4]*;     // non-GC-tracked array reference
Vec2&[]& e = new Vec2&[5]&;   // GC-tracked array of GC-tracked Vec2 references
```

Notes:

1. Fixed-size value arrays require a compile-time known size.
2. Managed array references are owned by the Ratchet runtime.
3. Manual/native arrays are explicit lifetime objects.

<a id="borrow-parameters" name="borrow-parameters"></a>
## Borrow Parameters

`in` and `inout` are keywords for explicit borrow-style parameter passing in free functions and methods.

Intent:

1. `in T p` means a **read-only borrow**.
2. `inout T p` means a **mutable borrow**.
3. `inout` arguments cannot alias in the same call.
4. Borrow parameters cannot escape function scope.
5. Borrow parameters cannot remain live across a coroutine `wait` point.
6. This model allows mutation without requiring value copies for large value types.

Syntax:

```cpp
struct Vec2 {
    float x;
    float y;
}

fn null translate(inout Vec2 v, float dx, float dy) {
    v.x = v.x + dx;
    v.y = v.y + dy;
}
```

<a id="structs-and-methods" name="structs-and-methods"></a>
## Structs and Methods

`struct` values are plain value types.

```cpp
struct Vec2 {
    float x;
    float y;
}
```

Methods are intended as an alternative call style over free functions, not a separate ownership model. In other words, they are syntax sugar over the same core parameter-passing rules.

Conceptual sugar direction:

```cpp
// method style
method null translate(float dx, float dy)

// equivalent free-function style
fn null Vec2_translate(inout Vec2 self, float dx, float dy)
```

<a id="examples" name="examples"></a>
## Examples

### 1) Smallest program shape

```cpp
fn bool program() {
    echo 1;
    return true;
}
```

### 2) Variables and expressions

```cpp
fn bool program() {
    int a = 10;
    int b = 20;
    int c = a + b;

    bool ok = c > 10;
    echo c;
    return ok;
}
```

### 3) Struct and method

```cpp
struct Vec2 {
    float x;
    float y;

    method null translate(float dx, float dy) {
        x = x + dx;
        y = y + dy;
    }
}

fn bool program() {
    Vec2 p = { x = 1.0f, y = 2.0f };
    p.translate(3.0f, -1.0f);
    return true;
}
```

### 4) Managed and manual references

```cpp
struct Enemy {
    int hp;
    bool alive;
}

fn bool program() {
    Enemy& tracked = new Enemy& { hp = 100, alive = true };
    Enemy* manual = new Enemy* { hp = 50, alive = true };

    free(manual);
    return true;
}
```

### 5) Coroutine-driven behavior

```cpp
struct Enemy {
    int hp;
    bool alive;
}

coroutine regen(Enemy& enemy, int amount) {
    while (enemy.alive) {
        enemy.hp = enemy.hp + amount;
        wait seconds(1.0f);
    }

    echo "regen stopped";
}
```

### 6) Event wait

```cpp
struct Hit {
    int damage;
}

coroutine shield(Enemy& enemy) {
    wait event Hit as hit;
    enemy.hp = enemy.hp - hit.damage;
}
```

<a id="current-status" name="current-status"></a>
## Current Status

Ratchet is experimental and under active development.

Current implementation direction:

1. Migrate the compiler/runtime to the current C3 toolchain.
2. Restore compilation of simple programs.
3. Move from the old stack-based VM to a typed register-based VM.
4. Use raw typed frame storage rather than boxed `Value[]` frames.
5. Lower parsed and semantically checked code into a simple MIR.
6. Compile MIR into VM bytecode.
7. Add coroutines after ordinary functions, calls, scopes, frame layout, and control flow are stable.

Near-term priority is correctness and architectural shape, not micro-optimization. The VM should still be designed around typed registers, known frame offsets, known field offsets, and direct function references so the implementation does not need a major rewrite later.

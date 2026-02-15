# Ratchet Language

**Ratchet** is an imperative language with familiar C-like syntax that sits between low-level systems languages and high-level scripting languages.

The main idea is simple: make storage and lifetime choices explicit **per variable**. Instead of hiding allocation behavior behind runtime defaults, Ratchet makes it visible in types so you can reason about where data lives.

At a high level:

1. `T` is a **stack-allocated value** by default.
2. `T&` is a **GC-tracked heap-allocated reference**.
3. `T*` is a **non-GC heap-allocated reference** with manual lifetime.

That model lets you start with straightforward code, then selectively move specific values to GC-tracked or manual heap storage only where performance and allocation behavior matters.

This split can also improve runtime behavior in mixed workloads. If hot paths are migrated away from GC-tracked storage and into manually managed storage, the collector has fewer objects and references to scan. In practice, that can reduce GC traversal work and make collection pauses smaller or less frequent.

This keeps the workflow ergonomic for infrequently ran code, while allowing for more precise control where it matters.

Ratchet is still being actively built and is **not fully working yet**. To try existing pieces, use the `0.0.5` proof-of-concept release, knowing only part of the language works there.

The long-term runtime direction is interpreted execution first, with a planned **JIT** and a possible optional **AOT** path later.

This document is the main language overview for now.

## Sections
1. [Design Goals](#design-goals)
2. [Syntax Basics](#syntax-basics)
3. [Types](#types)
4. [Functions](#functions)
5. [Values and Heap-Allocated References](#values-and-heap-allocated-references)
6. [Arrays](#arrays)
7. [Borrow Parameters](#borrow-parameters)
8. [Structs and Methods](#tructs-and-methods)
9. [Interfaces](#interfaces)
10. **[Examples](#examples)**

[#design-goals]: #design-goals
[#syntax-basics]: #syntax-basics
[#types]: #types
[#functions]: #functions
[#values-and-heap-allocated-references]: #values-and-heap-allocated-references
[#arrays]: #arrays
[#borrow-parameters]: #borrow-parameters
[#structs-and-methods]: #structs-and-methods
[#interfaces]: #interfaces
[#examples]: #examples

<a id="design-goals" name="design-goals"></a>
## Design Goals

1. Keep the language **small**, clear, and easy to embed.
2. Keep everyday code simple with **value semantics**.
3. Keep memory behavior explicit in types, so storage and ownership are visible at a glance.
4. Allow explicit control for cases where memory allocation strategy matters.
5. Be relatively small and relatively performant compared to similar scripting-oriented languages, especially for high-performance embeddable use cases like games and tools.

<a id="syntax-basics" name="syntax-basics"></a>
## Syntax Basics

Ratchet uses familiar C-like structure.

1. Programs are built from `fn` and `struct` declarations.
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
5. `string`
6. `null` (used for no-return function signatures)

### User types

1. `struct` value types
2. Heap-allocated reference forms using `&` and `*`

<a id="functions" name="functions"></a>
## Functions

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
2. Parameters are passed by value unless they are heap-allocated reference types (`T&` or `T*`).

<a id="values-and-heap-allocated-references" name="values-and-heap-allocated-references"></a>
## Values and Heap-Allocated References

Ratchet makes storage mode explicit in type spelling.

| Form | Meaning | Allocation | Copy behavior |
| --- | --- | --- | --- |
| `T` | Value type | Stack/inline (default) | Full value copy |
| `T&` | GC-managed heap-allocated reference | `new T&` | Reference copy |
| `T*` | Manual heap-allocated reference | `new T*` | Reference copy |

Quick examples:

```cpp
int  a = 5;   // stack value (copied)
int& b = {5}; // heap-allocated, GC-tracked
int* c = {5}; // heap-allocated, non-GC-tracked
```

Notes:

1. `T`, `T&`, and `T*` are distinct and not implicitly convertible.
2. `T*` values must be explicitly `free`d.

<a id="arrays" name="arrays"></a>
## Arrays

Array forms (using `Vec2`):

```cpp
Vec2[4] a = Vec2[4];          // stack-allocated array, size must be known at compile time
Vec2[]& c = new Vec2[4]&;     // GC-tracked array reference
Vec2[]* d = new Vec2[4]*;     // non-GC-tracked array reference
Vec2&[]& e = new Vec2&[5]&;   // GC-tracked array of GC-tracked Vec2 references
```

<a id="borrow-parameters" name="borrow-parameters"></a>
## Borrow Parameters

`in` and `inout` are keywords for explicit borrow-style parameter passing in free functions.

Intent:

1. `in T p` means a **read-only borrow**.
2. `inout T p` means a **mutable borrow**.
3. `inout` arguments cannot alias in the same call.
4. Borrow parameters cannot escape function scope.
5. This model allows mutation without requiring value copies for large stack values.

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

`struct` values are still plain value types.

```cpp
struct Vec2 {
    float x;
    float y;
}
```

Methods are intended as an alternative call style over free functions, not a separate ownership model. In other words, they are **syntax sugar** over the same core parameter-passing rules.

Conceptual sugar direction:

```cpp
// method style
method null translate(float dx, float dy)

// equivalent free-function style
fn null Vec2_translate(inout Vec2 self, float dx, float dy)
```

<a id="interfaces" name="interfaces"></a>
## Interfaces

Interfaces are part of the language direction as compile-time contracts.

```cpp
interface HasPosition {
    field float x;
    field float y;

    method float length2D() {
        return sqrt(x*x + y*y);
    }
}
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

### 3) Struct and method (`Vec2`)

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

### 4) Heap-allocated references

```cpp
struct Enemy {
    int hp;
}

fn bool program() {
    Enemy& tracked = new Enemy& { hp = 100 };
    Enemy* manual = new Enemy* { hp = 50 };

    free(manual);
    return true;
}
```

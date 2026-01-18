# Ratchet Language

***Still working on a v0.1, only some of the functionality
is currently implemented***

---

## Overview
Ratchet is an imperative programming language with a familiar C-like syntax that sits between low-level systems languages (C/C++/Rust) and high-level scripting languages (Lua/JS/Python). It targets fast iteration with GC by default, while still giving the programmer control over memory in performance-critical code. Think of Ratchet as a small, embeddable mid-level language.

The guiding principle is to keep most code simple and safe, but allow tighter control where it matters. Because the choice is per-variable, you can start with GC-managed code and later refactor hot paths without rewriting everything.

Ratchet allocates data on the stack by default and passes by **value**, unless the type is explicitly marked with `&` (e.g. `Foo&`) or `*` (e.g. `Foo*`). In Ratchet, references are handles to heap data and are allocated with `new T&` or `new T*`.

References in Ratchet are allocated on the **heap** and tracked by the GC.

Ratchet also allows **untracked references**, marked with `*` (e.g. `Foo*`). These "pointers" behave like references but are not tracked by the GC, leaving the responsibility to the programmer to free them when no longer needed.

Reference and pointer types specify how memory is allocated, so unlike C this is not allowed:

```
int a = 5;
int& b = &a;       // not allowed, '&' is part of the type, and a and b have different types
```

Instead, in Ratchet you would do something like:

```
int& a = new int&{5};  // a is an integer, but heap allocated
```

or, if you need a copy:

```
int a = 5;
int& b = new int&{a}; // creates a new int-ref with the value of a
```

## Why Ratchet
Ratchet is aimed at projects that want a scripting-like workflow but need optional control in hot paths, especially when embedding in games and tools.

* GC-by-default keeps iteration fast and code simple.
* `T*` lets you reduce GC pressure in critical sections without forcing manual memory everywhere.
* The runtime can stay small and easy to embed.

## Memory Model (Rules)
These are the core rules that guide how values and references behave:

* `T` is a value type stored inline and copied by value.
* `T&` is a GC-tracked handle to heap data.
* `T*` is a manual handle to heap data; the programmer owns the lifetime and must `free` it.
* A `T` value may contain `T&` fields; copying the `T` copies the handles (shallow) and keeps the referenced objects alive.
* There are no implicit or explicit conversions between `T`, `T&`, and `T*`.
* Allocation uses `new T&` or `new T*` for references or pointers respectively.

| Type | Allocation | Lifetime | Copy behavior | Typical use |
| --- | --- | --- | --- | --- |
| `T` | Stack/inline | Automatic | Value copy | Most data and logic |
| `T&` | Heap (GC) | GC-managed | Handle copy | Shared data, simple ownership |
| `T*` | Heap (manual) | Explicit `free` | Handle copy | Hot paths, manual control |

Example:

```ratchet
struct Enemy {
    int hp;
}

struct Squad {
    Enemy& leader; // GC-managed reference
}

fn null demo() {
    Enemy& boss = new Enemy& { hp = 100 };
    Squad a = { leader = boss };
    Squad b = a;         // shallow copy, same leader reference
    Enemy* scratch = new Enemy* { hp = 1 };
    free(scratch);
}
```

## Design Goals

* **Simple, Statically typed** imperative language.
* Interpreted in a bytecode **VM** with (maybe) optional JIT or AOT compilation to binary.
* **Struct-only** type system  
  * No classes  
  * No inheritance
* **Value semantics**
  * All types are value types by default
* **Reference types** are distinct from value types (T != T&)
* **Optional explicit memory control**
  * `T&` = GC tracked reference (managed)
  * `T*` = non-GC reference (unmanaged)
* No pointer arithmetic
* **Optional** debug leak detection for manual allocations
* **Interfaces as compile-time contracts** (no runtime dispatch in v1)
* **Methods on structs**
  * With implicit `this` / `self`

---

## Current State
***Skip this section to see the language features***.

Please note **ALL** of these will be heavily changed once the compiler rewrite lands. The current goal is to rebuild the pipeline so features can be added cleanly afterward, so this list only reflects temporary progress.

* ✅ Lexer/parser basics (custom-made, no yacc/lex)
* 🚧 Basic types (partially done, more to come)
* ✅ Bytecode VM basics
* ✅ Struct and function definitions
* ✅ Basic stack frame setup
* ✅ Basic primitive operations (math, assignment and logic)
* ✅ Struct field set/get
* ❌ Struct literals (planned)
* ❌ Methods (planned)
* ❌ Arrays (planned)
* ✅ Reference types (`T&` and `T*`)
* ❌ More optimization passes (planned, currently only collapses increment operations as a proof of concept)
* ❌ GC tracing (planned)
* ❌ Interfaces (planned)
* ❌ JIT (planned)
* ❌ LLVM IR or binary generation (maybe)
## Types

### Primitive Types

Built-in primitives all follow **value semantics**:

* `bool`
* `int`
* `float`
* `double`
* `string` (value semantics, uses GC-tracked reference internally)

More will come in the future such as:

* `char`
* `long`
* `ulong`
* `uint`
* `byte`

---

### Structs (Value Types)

```ratchet
struct Vec3 {
    float x;
    float y;
    float z;

    method float length() {
        return sqrt(x*x + y*y + z*z);
    }

    method void translate(float dx, float dy, float dz) {
        x += dx;
        y += dy;
        z += dz;
    }
}
```

**Rules:**

* `struct` defines a value type.
* Stored inline on stack, in arrays, or inside other structs.
* Safe to copy and return by value.
* No inheritance allowed.
* Structs may:
  * Implement interfaces.
  * Declare methods.

---

## Values vs References

### Pure Values

```ratchet
Vec3 v = { x = 1, y = 2, z = 3 };
int x = 42;
```

* Stored inline.
* Passed and returned by copy.
* No GC involvement.
* Always safe to return by value.

---

### GC-Managed References `T&`

```ratchet
Vec3& a = new Vec3& { x = 1, y = 2, z = 3 };
```

`T&` is a **GC-managed reference**:

* HeapTracker allocated.
* Copied by copying the reference (not the object).
* GC tracks the reference and keeps the object alive.

---

### Manual References `T*`

```ratchet
Vec3* b = new Vec3* { x = 4, y = 5, z = 6 };
free(b);
```

`T*` is a **manual reference (not traced by GC)**:

* Programmer-controlled lifetime.
* Must be explicitly freed.
* No pointer arithmetic.
* Failure to free results in a leak.
* Running in debug mode will detect leaks (TBD whether this will be included)

---

## Struct Literals
Struct literals use `{ field = value }` and work for values, `T&`, and `T*` (use `new T&` for `T&` and `new T*` for `T*`).

```ratchet
Vec3 v = { x = 1, y = 2, z = 3 };       // value
Vec3& a = new Vec3& { x = 1, y = 2, z = 3 };  // GC heap
Vec3* b = new Vec3* { x = 4, y = 5, z = 6 };  // manual heap
```

---

## Struct Methods

```ratchet
struct Foo {
    bool b;

    method bool bar() {
        return b;
    }

    method null set(bool v) {
        b = v;
    }
}
```

Lowered form:

```ratchet
fn bool Foo_bar(Foo& this)
fn null Foo_set(Foo& this)
```

Calls:

```ratchet
v.bar();   // lowers to -> Foo_bar(&v)
r.bar();   // lowers to -> Foo_bar(r)
p.bar();   // lowers to -> Foo_bar(p)
```

All calls are statically bound in v1.

---

## Interfaces

```ratchet
interface HasPosition {
    field float x;
    field float y;

    method float length2D() {
        return sqrt(x*x + y*y);
    }
}
```

Implementation:

```ratchet
struct Player : HasPosition {
    float x;
    float y;
    string name;
}
```

Usage:

```ratchet
fn null printDistance(HasPosition& p) {
    print(p.length2D());
}
```

Static only; no dynamic dispatch in v1.

---

## Arrays

Values:

```ratchet
Vec3[] arr = new Vec3[16];
arr[0] = { x = 1, y = 2, z = 3 };
```

References:

```ratchet
Vec3&[] gcRefs = new Vec3&[16];   // Array of Vec3 references
Vec3*[] rawRefs = new Vec3*[16];  // Array of Vec3 untracked references
```

GC vs manual arrays:

```ratchet
Vec3&[]& good  = new Vec3&[16];   // GC tracks both
Vec3*[]& leaks = new Vec3*[16];   // GC tracks array only, elements must be freed
```

Uniform typing:

```ratchet
arr[0] = v1;  // ok if types match
arr[1] = v2;  // error if Vec3& vs Vec3*
```

---

## Garbage Collection Rules

GC traces:

* `T&` stack locals
* `T&` fields
* `T&` array elements

Ignored by GC:

* Any `T*`
* Anything reachable only from `T*`

---

## Example Program

```ratchet
struct Vec3 {
    float x;
    float y;
    float z;

    method void translate(float dx, float dy, float dz) {
        x += dx;
        y += dy;
        z += dz;
    }
}

interface HasPosition {
    field float x;
    field float y;

    method float length2D() {
        return sqrt(x*x + y*y);
    }
}

struct Player : HasPosition {
    Vec3 position;
    string name;
}

fn Player& makeHero() {
    Player& p = new Player&{
        position = { x = 1.0, y = 2.0, z = 0.0 },
        name = "Hero"
    };
    return p;
}

fn bool program() {
    Player& p = makeHero();
    print(p.length2D());

    Vec3[]& positions = new Vec3[16];
    positions[0] = { x = 3, y = 9, z = 1 };

    Vec3* scratch = new Vec3* { x = 0, y = 0, z = 0 };
    scratch.translate(1,2,3);
    free(scratch);
}
```

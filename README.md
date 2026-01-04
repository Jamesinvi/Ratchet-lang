# 🔧 Ratchet Language

***Still working on a v0.1, only some of the functionality
is currently implemented***

---

## 🎯 Design Goals

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


## ⏳ Current State
***Skip this section to see the language features***.

Please not **ALL** of these will be heavily changed. The following list simply states what has been done, even if only in as a temporary implementation.

* ✅ Lexer/parser basics (custom-made, no yacc/lex)
* 🚧 Basic types (partially done, more to come)
* ✅ Bytecode VM basics 
* ✅ Struct and function definitions
* ✅ Basic stack frame setup
* ✅ Basic primitive operations (math, assignment and logic)
* ✅ Struct field set/get
* ❌ Constructors (planned)
* ❌ Methods (planned)
* ❌ Arrays (planned)
* ✅ Reference types (T& and T*)
* ❌ More optimization passes (planned)
* ❌ GC tracing (planned)
* ❌ Interfaces (planned)
* ❌ JIT (planned)
* ❌ LLVM IR or binary generation (maybe)

## 🧱 Types

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

## 📦 Values vs References

### Pure Values

```ratchet
Vec3 v = Vec3(1, 2, 3);
int x = 42;
```

* Stored inline.
* Passed and returned by copy.
* No GC involvement.
* Always safe to return by value.

---

### GC-Managed References – `T&`

```ratchet
Vec3& a = new Vec3(1, 2, 3);
```

`T&` is a **GC-managed reference**:

* HeapTracker allocated.
* Copied by copying the reference (not the object).
* GC tracks the reference and keeps the object alive.

---

### Manual References – `T*`

```ratchet
Vec3* b = new Vec3(4, 5, 6);
free(b);
```

`T*` is a **manual reference (not traced by GC)**:

* Programmer-controlled lifetime.
* Must be explicitly freed.
* No pointer arithmetic.
* Failure to free results in a leak.

---

## 🛠 Object Creation

```ratchet
Vec3 v = Vec3(1,2,3);       // value
Vec3& a = new Vec3(1,2,3);  // GC heap
Vec3* b = new Vec3(4,5,6);  // manual heap
```

---

## 🧩 Struct Methods

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

## 📜 Interfaces

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

## 📚 Arrays

Values:

```ratchet
Vec3[] arr = new Vec3[16];
arr[0] = Vec3(1,2,3);
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

## ♻ Garbage Collection Rules

GC traces:

* `T&` stack locals
* `T&` fields
* `T&` array elements

Ignored by GC:

* Any `T*`
* Anything reachable only from `T*`

---

## 🔍 Example Program

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
    Player& p = new Player();
    p.position.x = 1.0;
    p.position.y = 2.0;
    p.name = "Hero";
    return p;
}

fn bool program() {
    Player& p = makeHero();
    print(p.length2D());

    Vec3[]& positions = new Vec3[16];
    positions[0] = Vec3(3,9,1);

    Vec3* scratch = new Vec3(0,0,0);
    scratch.translate(1,2,3);
    free(scratch);
}
```

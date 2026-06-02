# Ratchet MVP Subset

Two scopes exist for now:

- Front end: features that parse and analyze.
- Backend: features that lower to MIR and run on the VM.

Anything outside the backend subset must stop with an explicit `not yet implemented` result. It must not be reported as success.

## Front-End Subset

Supported:

- types: `int`, `float`, `double`, `bool`, `null`, `struct`, `T&`, `T*`
- declarations: top-level `fn`, top-level `struct`, fields, methods, locals
- statements: expression statements, declarations, `if`, `else`, `while`, `return`, blocks, `echo`
- expressions: literals, variable access, assignment, arithmetic, comparison, boolean ops, free-function calls, method calls, field access, field assignment, `new T&`, `new T*`

Method rule:

- support `inout` for the receiver only
- ordinary parameters stay pass-by-value for now
- methods remain desugared free functions

## Backend Subset

Executable now:

- types: `int`, `float`, `double`, `bool`, `null`, plain structs by value
- declarations: top-level functions, locals
- statements: declarations, expression statements, `if`, `else`, `while`, `return`, blocks, `echo`
- expressions: literals, local load/store, arithmetic, comparison, boolean ops, direct free-function calls, struct value passing/return, field access, field assignment

Not executable yet:

- `T&`
- `T*`
- `new`
- method calls
- `inout`
- anything requiring heap or aliasing semantics

## Compiler Contract

After semantic analysis, every program must fall into exactly one bucket:

- invalid: parse or semantic error
- valid but not executable yet: explicit unsupported-feature result
- valid and executable: lower and run without MIR panics

If semantic analysis accepts a program that is inside the backend subset, MIR lowering must be total for it.

## Explicit Non-Goals

- arrays
- interfaces
- general `in`
- general `inout`
- generics
- multifile programs
- function overloading
- GC
- AOT

## Order

1. Freeze the front-end subset.
2. Freeze the backend subset.
3. Reject non-executable features explicitly after analysis.
4. Make MIR total for the backend subset.
5. Implement the register VM for the backend subset.
6. Keep semantic tests for the front end and execution tests for the backend.

## Bottom Line

Keep `methods`, receiver `inout`, `T&`, `T*`, and `new` in the front end.

Keep the first backend narrow: values, structs, locals, control flow, free-function calls, field access/assignment, and `echo`.

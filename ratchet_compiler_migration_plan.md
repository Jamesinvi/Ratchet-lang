# Ratchet compiler migration plan (AST -> Typed AST -> HIR -> MIR/CFG -> optimize -> backends)

A concrete, implementable roadmap for migrating the Ratchet compiler to a multi-IR pipeline.

## 0) Core semantics and constraints

### Ownership/handle model
- T = value (non-owning)
- T& = GC-managed heap handle
- T* = manually-managed heap handle (must be free'd)
- T@ = internal-only borrow/view (non-owning, non-escaping)

### Borrow (T@) rules (internal only)
- Cannot be stored in locals or struct fields
- Cannot be returned
- Cannot be passed to free
- Only exists transiently during lowering (especially method-call lowering)

### Keep concerns separated
- Parser produces syntax only.
- Semantic analysis resolves meaning (symbols + types).
- HIR removes surface sugar.
- MIR makes control flow explicit (CFG).
- Early lowering can be verbose; canonicalize/clean up with passes.

## 1) Pipeline overview

### A - Parse
Input: tokens  
Output: AST (syntax-only)

- AST nodes carry Span/source location.
- Identifiers are strings.
- Types are type-AST nodes (still syntax).

### B - Semantic analysis (name resolution + type checking)
Input: AST  
Output: Typed AST (AST annotated with IDs + TypeId) + diagnostics

Responsibilities:
- Build symbol tables (modules/structs/functions/fields/locals).
- Resolve identifiers -> IDs:
  - variable uses -> LocalId / SymbolId
  - function calls -> FnId
  - struct fields -> FieldId / field index
- Intern canonical types and assign TypeId to every expression.
- Validate semantic rules:
  - duplicates
  - invalid ops/casts
  - return checking (start conservative, improve later)

Non-responsibility:
- Entry point detection is NOT here.
  Do it in the driver/link step: executables require main; libraries do not.

### C - HIR (desugared, still tree-ish)
Input: Typed AST  
Output: HIR (typed + resolved, sugar removed)

HIR removes surface sugar while preserving spans/types for good diagnostics:
- Method calls -> plain function calls with implicit borrow
  - v.bar(a,b) -> Foo_bar(borrow(v), a, b) (borrow is internal, user never sees @)
- Optional later:
  - for -> while
  - interpolation -> concatenation/builder calls
  - compound assignments (+=, etc.)

### D - MIR (CFG-based mid-level IR)
Input: HIR  
Output: MIR with explicit CFG (basic blocks + terminators)

This is the workhorse IR for:
- optimization
- bytecode emission
- Cranelift/native emission

### E - Optimize (MIR passes)
Input: MIR  
Output: optimized MIR

Start with simple, stabilizing passes first.

### F - Backends
- MIR -> bytecode (VM)
- MIR -> Cranelift (JIT/AOT later)

## 2) MIR/CFG model: what CFG means

A Control-Flow Graph consists of:
- Nodes: basic blocks (straight-line statements)
- Edges: jumps/branches between blocks

MIR is the IR that contains this CFG structure.

## 3) Internal borrows without exposing @

### Method call lowering (internal borrow)
User writes:
- v.method()
- p.method() where p: T*
- r.method() where r: T&

Lowering:
- v.method() -> T_method(borrow(v), ...)
- p.method() -> T_method(borrow(*p), ...)
- r.method() -> T_method(borrow(*r), ...)

### free rules
- free(x) only accepts T* (owning manual handle).
- Never accepts T@.
- Later improvement: make free(p) consume p so use-after-free is a compile error.

### No implicit regime conversion
Do not implicitly coerce T* -> T& or otherwise cross ownership regimes.
If a function needs temporary access, model it as borrow intent and lower to @ internally.
(Optional future surface syntax: in T / inout T -> T@ / T@mut.)

## 4) Concrete MIR data model (suggested)

### Locals
- locals: Vec<LocalDecl> with TypeId (+ optional debug name/span)
- Convention:
  - _0 = return place
  - _1.._n = parameters
  - temps appended after params

### Place (lvalue)
Place = { base: LocalId, projections: Vec<Projection> }

Projection examples:
- Field(field_index)
- Deref (for T& / T* when accessing pointee)
- Index(temp_local) (arrays/slices later)

### Operand / Rvalue
Operands:
- Const(c)
- Copy(place) / Move(place) (if you track moves)
- Local(local_id) (optional style)

Rvalues:
- Use(operand)
- UnaryOp(op, operand)
- BinaryOp(op, a, b)
- Call(fn_id, args...)
- Aggregate(struct_id, fields...) (optional)

### Statements
- Assign(place, rvalue)
- Optional explicit checks:
  - CheckNull(operand)
  - CheckBounds(array, index)
  - etc.

### Terminators (end every block)
- Goto(bb)
- If(cond, then_bb, else_bb)
- Return
- Trap(reason) (optional)
- Switch(...) (later)

## 5) Block formation: when to create basic blocks

Create new blocks only for control-flow structure.

### Start a new block when:
1) You emit a terminator (Return, If, Goto, etc.)
2) You need a jump target (join points, loop headers, else blocks)

### Canonical lowering patterns

#### if (cond) { A } else { B }
- current: compute cond, If(cond, bb_then, bb_else)
- bb_then: emit A, then Goto(bb_join) unless it already terminated
- bb_else: emit B, then Goto(bb_join) unless it already terminated
- bb_join: continuation

#### while (cond) { body }
- current: Goto(bb_header)
- bb_header: compute cond, If(cond, bb_body, bb_exit)
- bb_body: emit body, Goto(bb_header)
- bb_exit: continuation

break -> Goto(bb_exit)  
continue -> Goto(bb_header)

#### Short-circuit && / ||
Lower into CFG:
- evaluate lhs
- branch to rhs evaluation or short-circuit-result path
- join block writes result temp

### Then canonicalize
Lowering can be dumb but correct (extra blocks/temps). Follow with cleanup:
- remove unreachable blocks
- merge trivial blocks (single pred/succ)
- simplify constant branches

## 6) Optimization plan (grow incrementally)

### Pass 1 - CFG cleanup
- remove unreachable blocks
- merge blocks when safe
- remove empty goto-only blocks

### Pass 2 - temp DCE
- remove locals/temps never read

### Pass 3 - constant folding + copy propagation
- fold operations on constants
- propagate simple assignments (x = const, y = x, etc.)

Later (once stable):
- bounds-check elimination (needs dominance facts)
- scalar replacement of aggregates
- inlining
- CSE (optional)

## 7) Backend roadmap

### Bytecode VM backend (first)
Why first:
- simplest backend
- great for debugging semantics
- easy to embed

MIR -> bytecode:
- linearize blocks
- emit jumps with fixups
- map locals to VM locals/slots

### Cranelift backend (later)
MIR -> CLIF:
- basic blocks map 1:1
- locals become vars/stack slots
- GC plan requirements:
  - identify GC-ref locals
  - mark safepoints (calls/allocations)
  - ensure refs are discoverable (stack maps / conservative strategy)

## 8) Embeddable VM checklist (design now, implement later)

- No global state: vm_create(config), vm_destroy(vm)
- Host hooks:
  - allocator hooks
  - print/log hook
  - module loading/import resolver hook
- Stable API for values:
  - push/pop ints/floats/bools/strings/handles
- GC boundary for T&:
  - host-held handles must be pinned/registered as roots or wrapped in VM-owned handles

## 9) Notes on current typecheck code (targeted fixes)

1) Move entry-point detection out of typecheck  
   Put it in driver/link.

2) Fix no return checking  
   Only error when return type is non-void and not all paths return.  
   Start conservative, refine with CFG later.

3) Stop mutating parser globals during typecheck  
   Put structTypes / name->idx / interning into a semantic context owned by the frontend.

4) Accumulate diagnostics  
   Prefer a diagnostics bag over a single error enum.

## 10) Milestones

### Milestone 1 - Frontend stabilization
- [ ] Semantic context (symbols + type interner)
- [ ] Name resolution to IDs
- [ ] Typed AST annotations (SymbolId, TypeId)
- [ ] Diagnostic aggregation
- [ ] Entry point check moved to driver

### Milestone 2 - HIR lowering
- [ ] Method calls -> function calls with implicit borrow
- [ ] Normalize lvalues/rvalues (explicit field access)
- [ ] Preserve spans/types

### Milestone 3 - MIR/CFG lowering
- [ ] Basic block builder
- [ ] Place + projections
- [ ] Lower if/while/return + short-circuit
- [ ] Optional explicit runtime checks

### Milestone 4 - MIR optimization
- [ ] CFG simplify
- [ ] Temp DCE
- [ ] Const fold / copy-prop

### Milestone 5 - Bytecode + VM
- [ ] MIR -> bytecode emitter
- [ ] VM run loop
- [ ] Embedding-friendly VM API skeleton

### Milestone 6 - Cranelift backend
- [ ] MIR -> CLIF emission
- [ ] GC reference handling plan (safepoints/stack maps)
- [ ] Optional AOT/JIT wiring

## 11) Done criteria
You are done with the IR migration when:
- Parse + typecheck + HIR + MIR all work.
- MIR can emit bytecode for real programs (if/while/calls/struct fields).
- CFG cleanup + DCE exists so MIR stays readable and stable.
- Method calls work via implicit borrows (no user-visible @).

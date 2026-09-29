# Learning LIL from the specification

This guide is the entry point for an LLM, tool author, or human implementing
LIL. It does not define new semantics. When it disagrees with a normative
specification, the normative specification wins.

## Reading order

1. Read the [language overview](../../README.md) for goals, scope, and explicit
   non-goals.
2. Read [Core IR v0](../specs/core-ir-v0.md) for the current executable
   language subset and validation rules.
3. Read [Wire Protocol v0](../specs/wire-protocol-v0.md) before constructing,
   transporting, or editing a graph.
4. Read the fixture nearest to the intended change. Fixtures are executable
   examples, not alternate specifications.
5. Run `lil render <snapshot.json>` to inspect the compiler's deterministic
   projection of a decoded graph. Treat that projection as read-only context.
6. Use `lil digest <snapshot.json>` as an edit base only after the document has
   been decoded and canonically re-encoded. A graph hash identifies a graph
   revision; it is never a symbol name or a model-local handle.
7. Treat graph edits as transactions. The current `propose-rename` command is
   non-persistent and returns a candidate only after its base digest and graph
   validation both succeed.
8. Read [LLVM lowering v0](../specs/llvm-lowering-v0.md) only when changing
   backend behavior. It specifies a projection from a validated graph, never
   a second language syntax.

## Current implementation boundary

The bootstrap verifier decodes a `lil.wire/0` snapshot envelope into a typed
`lil.cpg/0` graph, then validates that graph. JSON is one replaceable transport
adapter; it is not a source language or a semantic data structure. The current
validator checks versions, the declared target, required fields, declaration
IDs and names, declaration shapes, scalar types, entry-block identity, and the
v0 `UnsafeFFI` effect. It also validates the implemented `const` →
`add.wrapping` → `return` operation path: integer range, operation identity,
operand types, terminator position, local SSA reference, result index, and
return type. The same subset can be evaluated by the reference interpreter.
Semantic failures identify an error code, the smallest relevant graph object,
and the violated rule, so repair can be scoped to a graph node instead of a
text location.

It does **not** yet validate operation schemas, SSA dominance, block edges,
effect propagation, layout, ownership, borrow lifetimes, cleanup, async, or
native code generation. Do not infer that an accepted snapshot has those
properties; consult the phase and rule stated in the diagnostic or spec.

## Authoring rules

- Treat the graph, rather than a rendered text file or JSON wire document, as
  the source of truth.
- Include every required field and use exact version strings.
- Give each declaration a unique, stable `id` and a unique module-local `name`.
- Declare the target explicitly. The initial accepted targets are Apple Silicon
  macOS, Intel macOS, and Linux x86-64.
- Use only the currently defined scalar types unless the Core IR version adds a
  feature-gated extension.
- Treat `UnsafeFFI` as an explicit boundary. It is never inferred.
- A `const` creates result index `0`; a `return` must be the final operation
  and must refer to an earlier local result of the function's declared type.
- `add.wrapping` takes two earlier local results of the same integer type and
  returns result index `0`; overflow is defined modulo that type's bit width.
- Prefer a minimal valid graph construction or fixture before proposing a new
  graph construct.

## How to extend the language

Every new semantic feature should add, in the same change:

1. A normative rule in the Core IR specification.
2. Its serialized form and versioning behavior in the wire protocol.
3. A valid fixture, an invalid fixture, and verifier tests.
4. A concise update to this guide’s implementation boundary.

This keeps the language learnable: an LLM can retrieve one small rule plus
positive and negative examples instead of guessing from compiler behavior.

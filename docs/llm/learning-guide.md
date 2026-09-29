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

## Current implementation boundary

The bootstrap verifier decodes a `lil.wire/0` snapshot envelope into a typed
`lil.cpg/0` graph, then validates that graph. JSON is one replaceable transport
adapter; it is not a source language or a semantic data structure. The current
validator checks versions, the declared target, required fields, declaration
IDs and names, declaration shapes, scalar types, entry-block identity, and the
v0 `UnsafeFFI` effect.

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

# Learning LIL from the specification

This is the entry point for an LLM, compiler-service author, or human tooling
author. It adds no semantics: when it disagrees with a normative document,
[Latent ISA v0](../specs/latent-isa-v0.md) wins.

## What LIL is

LIL is not textual source code. A compatible model emits `u16` semantic token
IDs. The compiler service supplies a legal-next-token constraint before each
emission, decodes accepted IDs into a typed latent program graph, validates the
graph, and commits the graph together with the exact token ABI version.

Human renderings are inspection output only. Do not generate braces, keywords,
variable names, JSON, or a file format as a substitute for a token stream.

## Reading order

1. Read the [language overview](../../README.md) for goals and non-goals.
2. Read [Latent ISA v0](../specs/latent-isa-v0.md), especially §2.1 and §2.2,
   before emitting or decoding any token.
3. Read [the ABI examples](../../examples/latent-isa.md) and the arithmetic
   [debugger projection](../../examples/arithmetic.lil). Start from anonymous
   typed function graphs such as `F[2,L,L>L](+[0,1])`, not a `main` function.
4. Read [Core IR v0](../specs/core-ir-v0.md) only when changing the temporary
   typed-graph/backend support layer.
5. Read [LLVM lowering v0](../specs/llvm-lowering-v0.md) only when changing
   the experimental backend projection.

## Function-graph authoring protocol

The model-facing ABI must express a function graph without names or an export:

1. Open a function graph with its arity and input/result types.
2. Emit operation nodes whose operand slots are constrained by the expected
   types and the available argument/value nodes.
3. Reference arguments and prior values by compact local handles, never names.
4. Close the graph only once every required result is present.

For example, the debugger traversal

```text
F[2,L,L>L](+[0,1])
```

constructs an anonymous `i64 × i64 → i64` graph. The model needs no function
name, visibility, entrypoint, syntax, temporary names, or braces. The existing
`lil.token/0` numeric stream is retired backend scaffolding, not an authoring
protocol.

## Service rules

- Request the next-token constraint before every token. A constraint is
  authoritative for that exact graph/projection state.
- Treat model-local references as positional handles, not saved names.
- Commit only a fully decoded graph with its ABI version and base graph digest.
- If a token is rejected, retain the prior graph state and request the new
  constraint; do not repair a textual representation.
- Ask the service for scoped symbol/type projections when an operation needs
  a repository definition. Account for that retrieval as part of task cost.
- Use a disassembly only for review, diagnostics, or context. It cannot be
  parsed back into a program.

## Extending the language

Every token-ABI extension must include:

1. Stable numeric IDs or a stable numeric range.
2. Exact decoder transitions and legal-next constraints.
3. Result types, effects, failure, cancellation, and lowering semantics.
4. Direct-decoder positive and negative tests.
5. Whole-task evidence that the operation reduces model information cost
   without hiding a material behavior choice.

This keeps LIL learnable: the model retrieves a compact ABI rule and receives
only legal next choices instead of guessing a textual grammar.

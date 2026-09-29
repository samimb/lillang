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
3. Read [the ABI examples](../../examples/latent-isa.md) for the executable
   `lil.token/0` vector and expected constraints.
4. Read [Core IR v0](../specs/core-ir-v0.md) only when changing the temporary
   typed-graph/backend support layer.
5. Read [LLVM lowering v0](../specs/llvm-lowering-v0.md) only when changing
   the experimental backend projection.

## `lil.token/0` authoring protocol

For the implemented subset, emit this sequence of semantic choices:

1. `1` to begin the module.
2. `16` to begin `main() -> i32`.
3. In the function body, choose `32` (constant), `33` (wrapping addition), or
   `34` (return), but only when that token is in the next-token constraint.
4. After `32`, emit an ID from `4096..8191`; it represents `id - 6144`.
5. After `33` or `34`, emit only a permitted local-value reference from the
   reported `12288 + n` range. Never invent a value name.
6. After a return, emit `17`, then `2`.

For example, the vector

```text
1 16 32 6164 32 6166 33 12288 12289 34 12290 17 2
```

constructs a graph whose `main` returns `42`. The model needs no syntax,
temporary variable names, braces, or manually repeated type annotations.

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

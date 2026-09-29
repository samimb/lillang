# LIL Latent ISA v0

**Status:** normative design direction  
**Purpose:** define the LLM-native authoring representation before expanding the conventional compiler subset.

## 1. Primary representation

LIL is not a textual programming language. A model emits a versioned stream of
semantic instruction tokens. A constrained decoder maps that stream directly
to a typed latent program graph (LPG). The LPG is the committed program.

```text
model token IDs → constrained semantic decoder → typed latent graph
                → validation / patching           → LLVM, WASM, or another backend
```

There is no lexer, parser, brace matching, or name lookup in the model output
path. A human-readable LIL rendering is a disassembler for inspection and
review; it is not the source language and need not round-trip.

## 2. Token ABI

A token ABI defines semantic instructions, operand slots, type families, and
the decoder state in which each token is legal. It is versioned by model,
tokenizer, vocabulary mapping, and language feature set.

For example, an `add<i64>` instruction can constrain its next two outputs to
existing values producing `i64`. The decoder MUST reject a token that is not
legal in its current typed state. Token IDs may be the immediate program
representation for a compatible model, but a commit MUST also record the
decoded graph and exact token-ABI version so it remains reproducible after a
tokenizer changes.

## 3. Latent graph model

The graph is immutable, SSA-like, type-directed, and effect-aware. Values are
identified structurally; human names are optional metadata. Short model handles
such as `F42`, `T17`, and local value slots are valid only within a projection
session and resolve to stable graph identities before commit.

The initial core favors composition over mutation. Effects such as `Net`,
`DB.Read`, `DB.Write`, `FS.Read`, `FS.Write`, `Clock`, `Random`, and `Unsafe`
are part of function and operation types. The model does not spend tokens on
boilerplate that is uniquely implied by a typed operation, including ordinary
error propagation, cleanup, or ownership decisions when no semantic choice is
lost.

## 4. Semantic operators

LIL is an ISA for model reasoning, not merely a compact syntax for low-level
instructions. Its operation set may contain stable, typed semantic operators
such as composition, `MAP`, `FILTER`, `REDUCE`, `RETRY`, `TIMEOUT`, `PARALLEL`,
`TRANSACTION`, `VALIDATE`, `AUTHZ`, HTTP, SQL, serialization, logging, and
metrics. Each operator MUST have precise effect, failure, cancellation, and
lowering semantics. An operator is admitted when it reduces whole-task model
information cost without hiding a material behavior choice.

## 5. Model memory and edits

The compiler service is part of the authoring architecture. It provides scoped
symbol/type summaries, compact handles, legal-next-token constraints, explicit
retrieval, diagnostics, and atomic graph patches. Definitions are injected when
needed rather than requiring an entire repository in context.

Edits target graph identities and carry a base graph digest. A patch is either
validated and committed atomically or rejected. The primary measurement is the
total information and interaction cost to implement and safely change a task:
semantic output tokens, retrieved context, constrained-decoding retries, tool
calls, compile time, and human review effort.

## 6. Current prototype boundary

The Zig prototype currently validates a tiny typed graph subset, renders a
disassembly, applies a rename transaction, and lowers straight-line integer
arithmetic to LLVM IR. It is useful infrastructure only. JSON is a temporary
test wire adapter; its syntax and the rendered `.lil` view are not LIL source.
The next implementation priority is a token-ABI registry and constrained
decoder, not broader conventional-language syntax or backend features.

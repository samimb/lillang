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

### 2.1 Target function-graph shape

The first useful LIL function is an anonymous typed graph, not a public entry
point. For two `i64` inputs and one `i64` output containing one add node, the
compact debugger traversal is:

```text
F[2,L,L>L](+[0,1])
```

`F` opens a function graph; `2` is the arity; the first two `L` values are
argument types; the final `L` is the result type; `+` is typed add; and `0` and
`1` reference argument nodes. `F2LLL+A0A1` is an even denser mnemonic for the
same graph. These spellings are visual explanations of semantic tokens, never
a textual grammar the model must parse or emit.

The human debugger projection is deliberately ordinary but not source:

```text
function (arg0: i64, arg1: i64) -> i64
  add(arg0, arg1)
```

Names, visibility, module exports, and backend entrypoints are optional graph
metadata. They must not be required to express the function graph itself.

### 2.2 Executable token ABI: `lil.graph/1`

The current model-facing decoder assigns the following raw `u16` vocabulary
IDs. The numbers are the program; labels are documentation for ABI authors.

| ID | Semantic token |
| --- | --- |
| `1847` | anonymous function with two inputs and one result (`fn2`) |
| `3912` | `i64` type |
| `8122` | `add<i64>` |
| `7201` | argument node 0 |
| `7202` | argument node 1 |

The complete program is exactly:

```text
1847 3912 3912 3912 8122 7201 7202
```

After `1847`, only three type-slot tokens are legal. After `8122`, only the
two existing `i64` argument-node tokens are legal. The final add node is the
function result, so no `return`, name, brace, module, or source terminator is
needed. The decoder constructs the corresponding typed graph directly.

### 2.3 Retired bootstrap ABI: `lil.token/0`

The first executable decoder is intentionally narrow and is retained only as
backend test scaffolding. It hard-codes a public `main() -> i32`; it is **not**
the LIL model ABI and must not guide examples or future token allocation. A
replacement starts from the anonymous function graph above.

| Token ID or range | Meaning | Legal decoder state |
| --- | --- | --- |
| `1` | begin one module | start |
| `2` | end the module | after a completed function |
| `16` | begin the sole `main() -> i32` function | module body |
| `17` | end that function | after its return |
| `32` | append `const i32`; request one literal token | function body |
| `33` | append wrapping `add i32`; request two local `i32` references | function body |
| `34` | append `return i32`; request one local `i32` reference | function body |
| `4096..8191` | signed 12-bit `i32` literal; `id - 6144` | immediately after `32` |
| `12288..16383` | local value reference `id - 12288` | only in a requested `i32` operand slot |

`lil.token/0` accepts exactly one function, no parameters, no effects, and one
return. Every `const` and `add` appends one value to the local value table.
Reference token `12288 + n` is legal only when value `n` already exists and
has the required `i32` type. Therefore an add after two constants admits only
`12288` and `12289`, not a guessed name, a future value, an integer literal, or
an arbitrary token.

The complete vector for `main() -> i32 { return wrapping_add(20, 22) }` is:

```text
1 16 32 6164 32 6166 33 12288 12289 34 12290 17 2
```

The decoder translates it directly into typed graph nodes, assigns stable
graph identities, validates the result, and records `lil.token/0` with the
commit. It never parses a source string.

### 2.4 Required decoder behavior

Before sampling each model token, the compiler service MUST expose a
`NextTokenConstraint` derived from decoder state. In `lil.token/0` that is one
of: an exact finite ID set, the literal range, a type-filtered local-reference
range, or terminal. A service MUST reject an out-of-constraint ID before graph
construction. Final graph validation remains mandatory after the stream closes.

An ABI extension MUST allocate new stable IDs or ranges, state the exact legal
decoder transitions, define result types/effects/failure behavior, and add
positive and negative decoder tests. It MUST NOT assign semantic meaning by
parsing a human-rendered name.

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

The normative admission policy and first candidate set are in
[Semantic operator admission v0](semantic-operators-v0.md).

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

[Scoped model projections v0](model-projections-v0.md) defines the implemented
read-only handle and accounting boundary.

## 6. Current prototype boundary

The Zig prototype now decodes the first raw token-ID subset directly into a
tiny typed graph, reports legal-next-token constraints, renders a disassembly,
and lowers straight-line integer arithmetic to LLVM IR. The graph and backend
remain supporting infrastructure. Human renderings are not LIL source. The next
implementation priority is broadening the token ABI and constrained decoder,
not adding conventional-language syntax or a new wire format.

# LIL examples

LIL has no editable `.lil` or JSON source files. The model-facing artifact is
a versioned stream of token IDs, and the typed graph is committed after the
stream is accepted by the constrained decoder.

[`latent-isa.md`](latent-isa.md) documents the first ABI vector and the future
semantic shapes it is intended to grow into. The current `lil` command accepts
the vector only to inspect the implementation; comma separation is a CLI
convenience, not language syntax.

The `.lil` files are curated disassemblies for review, documentation, and LLM
context. They are deliberately not parsed or round-tripped. They show the
semantic shape that a token ABI must eventually encode:

- [`arithmetic.lil`](arithmetic.lil) — implemented `lil.token/0` arithmetic.
- [`fetch_user.lil`](fetch_user.lil) — result propagation and HTTP/serde effects.
- [`retry_timeout.lil`](retry_timeout.lil) — retry and timeout policy.
- [`parallel_lookup.lil`](parallel_lookup.lil) — structured parallel composition.
- [`add_i64-comparison.md`](add_i64-comparison.md) — end-to-end LIL/C prompt,
  debugger, compiler, performance, and token-accounting comparison.

[`add_i64.lil`](add_i64.lil) is different: it is an opaque binary artifact
containing raw `lil.graph/1` token IDs. It is compiled and inspected directly:

```sh
./lil debug examples/add_i64.lil
./lil build examples/add_i64.lil -o add_i64
./add_i64
```

```sh
# Retired backend-only `lil.token/0` smoke test; not the model ABI.
zig build run -- eval-token-ids 1,16,32,6164,32,6166,33,12288,12289,34,12290,17,2

# After the add opcode, only references to the two existing i32 values are legal.
zig build run -- legal-next-token-ids 1,16,32,6164,32,6166,33
```

`render-token-ids` produces a human disassembly for review only. The old Zig
graph-construction sample remains in [`tools/minimal_graph.zig`](../tools/minimal_graph.zig)
as backend-support infrastructure, not as an authoring example.

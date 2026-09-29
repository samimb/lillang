# LIL examples

LIL has no editable `.lil` or JSON source files. The model-facing artifact is
a versioned stream of token IDs, and the typed graph is committed after the
stream is accepted by the constrained decoder.

[`latent-isa.md`](latent-isa.md) documents the first ABI vector and the future
semantic shapes it is intended to grow into. The current `lil` command accepts
the vector only to inspect the implementation; comma separation is a CLI
convenience, not language syntax.

```sh
# module → main() -> i32 → const 20 → const 22 → add → return → close
zig build run -- eval-token-ids 1,16,32,6164,32,6166,33,12288,12289,34,12290,17,2

# After the add opcode, only references to the two existing i32 values are legal.
zig build run -- legal-next-token-ids 1,16,32,6164,32,6166,33
```

`render-token-ids` produces a human disassembly for review only. The old Zig
graph-construction sample remains in [`tools/minimal_graph.zig`](../tools/minimal_graph.zig)
as backend-support infrastructure, not as an authoring example.

# LIL examples

Each example has three distinct views:

- [`latent-isa.md`](latent-isa.md) shows the intended model-facing semantic-token and constrained-decoder form.
- `*.json` is temporary graph wire transport for the current prototype, not LIL source.
- `*.lil` is the deterministic human disassembly of that graph, not an independent editable source format.

| Example | Demonstrates |
| --- | --- |
| [`arithmetic.lil`](arithmetic.lil) | graph disassembly for typed constants, wrapping addition, and a return value |
| [`wraparound.lil`](wraparound.lil) | graph disassembly for explicit `i8` modular overflow semantics |

```sh
zig build run -- render examples/arithmetic.json
zig build run -- check examples/arithmetic.json
zig build run -- eval examples/arithmetic.json
```

The Zig graph-construction sample is intentionally kept in [`tools/minimal_graph.zig`](../tools/minimal_graph.zig), outside the LIL showcase.

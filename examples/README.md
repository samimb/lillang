# LIL examples

Each example has two views of the same program:

- `*.json` is the current canonical graph wire snapshot, consumed by the verifier, interpreter, and bootstrap compiler.
- `*.lil` is the deterministic human/LLM projection of that graph. It is the readable LIL code view, not an independent editable source format.

| Example | Demonstrates |
| --- | --- |
| [`arithmetic.lil`](arithmetic.lil) | typed constants, wrapping addition, and a return value |
| [`wraparound.lil`](wraparound.lil) | explicit `i8` modular overflow semantics |

```sh
zig build run -- render examples/arithmetic.json
zig build run -- check examples/arithmetic.json
zig build run -- eval examples/arithmetic.json
```

The Zig graph-construction sample is intentionally kept in [`tools/minimal_graph.zig`](../tools/minimal_graph.zig), outside the LIL showcase.

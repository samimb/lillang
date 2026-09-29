# LLVM lowering v0

**Status:** experimental implemented subset
**Scope:** parameter-free `pub fn main() -> i32` with integer `const`,
`add.wrapping`, and `return`.

> **Design authority:** [Latent ISA v0](latent-isa-v0.md) defines the source
> path. This lowering validates only an early latent-graph/backend boundary.

This is the first native-pipeline boundary. The canonical graph is validated
before lowering. LLVM IR is a backend representation, not the LIL source or
canonical program graph.

## Mapping

| Core IR node | LLVM IR |
| --- | --- |
| `const` | `add <type> 0, <literal>` producing a stable temporary |
| `add.wrapping` | plain LLVM `add` without `nsw` or `nuw` flags |
| `return` | `ret i32 <temporary>` |

Graph operation IDs are mapped to sequential `%v0`, `%v1`, … temporaries in
canonical operation order. This prevents arbitrary graph IDs from becoming
backend identifiers while later debug metadata can retain the source graph ID.

The command below emits the IR for inspection or a later linker stage:

```sh
zig build run -- lower-token-ids 1,16,32,6164,32,6166,33,12288,12289,34,12290,17,2
```

The repository's native vertical-slice harness compiles this emitted IR with
Zig's LLVM-backed toolchain and verifies that the native process returns `42`:

```sh
bash scripts/test-native-vertical-slice.sh
```

For the supported host-native subset, the bootstrap build command combines
validation, lowering, and linking:

```sh
bash scripts/build-native.sh <comma-separated-token-ids> <output-path>
```

The v0 lowering accepts only a parameter-free, effect-free public `main` with
an `i32` result. Branches, calls, structs, `Result`, ownership, optimization,
debug metadata, object emission, and linking remain outside this implemented
subset.

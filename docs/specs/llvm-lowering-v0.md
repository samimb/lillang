# LLVM lowering v0

**Status:** implemented subset  
**Scope:** parameter-free `pub fn main() -> i32` with integer `const`,
`add.wrapping`, and `return`.

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
zig build run -- lower-llvm fixtures/valid/minimal-macos.json
```

The v0 lowering accepts only a parameter-free, effect-free public `main` with
an `i32` result. Branches, calls, structs, `Result`, ownership, optimization,
debug metadata, object emission, and linking remain outside this implemented
subset.

# LIL Core IR v0

**Status:** experimental supporting infrastructure
**Scope:** the executable semantic subset used to validate early typed-graph and native-backend work.

> **Design authority:** [Latent ISA v0](latent-isa-v0.md) defines LIL's
> primary authoring model. This Core IR draft is a temporary graph-layer
> experiment; where the two documents conflict, Latent ISA v0 wins.

This document defines the first canonical program graph (CPG) subset. It deliberately excludes generics, closures, async, tasks, exceptions/unwinding, header import, and automatic ownership inference. Those features require extensions after this subset has a conformance suite.

## 1. Conventions

Every CPG object has an immutable `id`, a UUID encoded as lowercase text in the wire format. IDs are globally unique within a graph revision and are never reused. IDs are structural references; names are not references.

An operation produces zero or more SSA values. A value is addressed by the pair `(operation_id, result_index)`. Each such pair has exactly one type. A value may be used only by an operation in its defining block or in a block dominated by its defining block. A block parameter is defined at the entry of its block.

The canonical graph has exactly one module root and exactly one declared target. Phase 0 accepts `aarch64-macos-none` (the primary developer target), `x86_64-macos-none`, and `x86_64-linux-gnu`. Another target is a distinct build input, not an implicit compiler default.

## 2. Module schema

```text
Module {
  id: ModuleId,
  format_version: "lil.cpg/0",
  language_version: "0.1",
  target: TargetTriple,
  required_features: Set<Feature>,
  optional_metadata: Map<String, Bytes>,
  dependencies: List<Dependency>,
  declarations: List<Declaration>
}

Dependency { module_name: String, source_digest: Digest, version: String }
Declaration = StructDecl | FunctionDecl | ExternalFunctionDecl
```

Declaration names are unique within their module. Exported names form the stable link and diagnostic identity. A function body may reference only declarations in its module or declared dependencies.

## 3. Types and layout

```text
Type = unit | bool | i8 | i16 | i32 | i64 | u8 | u16 | u32 | u64
     | f32 | f64 | ptr<AddressSpace, Type> | named<StructId>
     | result<OkType, ErrorType>
StructDecl { id: StructId, name: String, fields: List<Field>, repr: native | c }
Field { name: String, type: Type }
```

`repr: native` has compiler-controlled layout and cannot cross an ABI boundary. `repr: c` follows the declared target C ABI and may contain only C-ABI-compatible field types. Recursive structures must use `ptr`; direct recursive values are invalid. `result` is a language type and has no C ABI in v0.

Integer arithmetic has no implicit widening, narrowing, or signedness conversion. Arithmetic operation families are named `checked`, `wrapping`, or `saturating`. A checked operation returns `result<T, ArithmeticError>`; wrapping and saturating operations return `T`.

## 4. Functions, blocks, and operations

```text
FunctionDecl {
  id: FunctionId,
  name: String,
  visibility: private | public,
  parameters: List<Parameter>,
  result: Type,
  effects: Set<Effect>,
  body: FunctionBody
}
FunctionBody { entry: BlockId, blocks: List<Block> }
Block { id: BlockId, parameters: List<BlockParameter>, operations: List<Operation> }
```

Every block ends in exactly one terminator and no operation follows a terminator. The entry block parameters are the function parameters, in declared order and with identical types. A non-entry block parameter receives one argument from every predecessor at the same index and type.

The permitted v0 operations are:

| Operation | Results | Validation rule |
| --- | --- | --- |
| `const` | one | Literal fits its declared scalar type. |
| `add/sub/mul` | one | Both operands have the operation's identical integer type. |
| `eq/lt/le` | one `bool` | Operands have identical comparable scalar types. |
| `struct.init` | one | Fields are supplied once, in declaration order and field type. |
| `struct.get` | one | Operand is the declared struct type; result is the selected field type. |
| `call` | function result | Arguments, effects, and result match the callee declaration. |
| `external.call` | external result | Declaration has `UnsafeFFI`; arguments have its ABI-safe types. |
| `result.ok` / `result.err` | one `result` | Payload has the selected result component type. |
| `result.unwrap_or_branch` | none | See terminators below. |
| `br` | none | Target argument types match target block parameters. |
| `cond_br` | none | Condition is `bool`; each edge type-checks independently. |
| `return` | none | Returned value has the function result type. |
| `trap` | none | Has a stable diagnostic code and never returns. |

`result.unwrap_or_branch value, ok_block(args...), err_block(args...)` is a terminator. `value` must be `result<O, E>`; the first argument on the ok edge is `O`, and the first argument on the error edge is `E`. Remaining arguments are checked like `br`. This is the sole `Result` control-flow primitive in v0.

### Implemented operation subset

The following node schema is implemented by the Phase 0 verifier. It is a
strict subset of the table above; an operation absent here is specified but not
yet accepted by the bootstrap implementation.

```text
Block {
  id: BlockId,
  parameters: List<BlockParameter>,
  operations: NonEmptyList<Operation>
}
BlockParameter { id: ValueId, type: ScalarType }

Operation = ConstInteger | WrappingAdd | Return
ConstInteger { id: OperationId, type: IntegerType, value: i64 }
WrappingAdd { id: OperationId, type: IntegerType, left: ValueRef, right: ValueRef }
Return { id: OperationId, value: ValueRef }
ValueRef { operation_id: OperationId, result_index: u32 }
```

`ConstInteger` has one result at index `0`. Its signed `i64` wire value MUST
fit the selected integer type. `Return` is a terminator and has no result. It
MUST be the final operation of its block. Its `ValueRef` currently resolves
only to an earlier operation in the same block, MUST use result index `0`, and
MUST have the function's declared result type. Operation IDs are unique within
a function. These same rules apply regardless of whether a graph was created
by a model token decoder, a Zig API, or a future graph persistence decoder.

`WrappingAdd` has one result at index `0`. Both inputs MUST refer to earlier
local results at index `0`, have the operation's declared integer type, and
are added modulo that type's bit width. It is never a terminator. Checked and
saturating arithmetic need their own result/error semantics and are not yet in
the implemented subset.

### Implemented rendering

The renderer projects this subset deterministically for inspection and model
context. It is not parseable source and cannot replace the graph:

```text
module module.example target aarch64-macos-none
pub fn main() -> i32 {
  block entry:
    %op.left: i32 = const 20
    %op.right: i32 = const 22
    %op.answer: i32 = add.wrapping %op.left[0], %op.right[0]
    return %op.answer[0]
}
```

The renderer emits declarations, blocks, and operations in canonical graph
order. Value references retain their operation ID and result index so a model
can cite a precise graph object when proposing a transaction.

## 5. Effects and unsafe calls

```text
Effect = UnsafeFFI
```

The v0 effect set is intentionally a singleton. A function's declared effects must be a superset of every direct callee effect. `external.call` requires `UnsafeFFI` on its enclosing function. A function with no effects is pure and may call only other pure functions. `Net`, `FS`, allocation, and capability values are deferred until the runtime and authority model are specified together.

An `ExternalFunctionDecl` records its C symbol, calling convention, argument and result ABI types, link library, and target. It is not callable through `call`; `external.call` makes the unsafe boundary visible in the graph.

## 6. Graph validity

A module is valid only when all of the following hold:

1. All IDs and declaration names are unique in their defined namespaces.
2. References resolve within the module or its declared dependencies.
3. Every block is reachable from a function entry, and every terminator target belongs to the same function.
4. SSA definitions dominate every use; no use is reachable before its definition in the same block.
5. Every operation satisfies its typing, effect, and ABI rule.
6. Every control-flow edge supplies exactly the target block parameters with identical types.
7. No `native` struct, `result`, or non-ABI-safe pointer is passed to `external.call`.

The verifier reports a stable error code, the smallest relevant graph object ID,
and the violated rule. The implemented subset does not yet attach observed and
expected values; those are required when richer type and CFG diagnostics land.
A graph is rejected as a whole; there is no partially valid committed revision.

## 7. Deferred semantics

Memory ownership, mutation, borrowing, destruction, allocation, panic unwinding, concurrency, closures, generics, and async are not represented in v0. Phase 1 can only use immutable scalar/struct values and opaque pointers at explicitly unsafe external boundaries. Adding any of these semantics requires a feature-gated Core IR revision and conformance tests.

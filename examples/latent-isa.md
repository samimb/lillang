# Latent ISA examples

This page documents token ABI vectors and semantic shapes. It is not source
code: token IDs are emitted by a compatible model and decoded directly to a
typed graph. Whitespace and comments below exist solely for human inspection.

## Arithmetic

The target representation for `add : i64 × i64 → i64` is the function graph:

```text
F[2,L,L>L](+[0,1])
```

Its executable `lil.graph/1` model output is:

```text
1847 3912 3912 3912 8122 7201 7202
```

| Graph component | Meaning |
| --- | --- |
| `F[2,L,L>L]` | anonymous function with two `i64` arguments and an `i64` result |
| `+` | typed add node |
| `0`, `1` | argument-node references |

`F2LLL+A0A1` is the same graph in a denser mnemonic. The `F…` spellings are
debugger notation only; the seven numeric IDs are the model program. Its decoder
allows only the two existing `i64` argument nodes in the add slots. The debugger
view is [`arithmetic.lil`](arithmetic.lil).

The current `lil.token/0` numeric stream and `main() -> i32` command are
retired backend scaffolding for testing LLVM lowering. They are not an example
of the next authoring ABI.

## Error-propagating composition

```text
PROPAGATE(JSON_DECODE<User>, HTTP_GET, ARG0)
```

This is a semantic shape, not a v0 token vector. When admitted to the ABI,
`PROPAGATE` will require a result-producing child and derive the enclosing error
path. It will not ask the model to emit temporary variables or textual error
branches.

## Scoped symbol memory

```text
T17 = User{id:str,name:str}
F42 = get_user(uuid) -> Result<T17,FetchError> ![Net]
F91 = save_user(T17) -> Result<unit,DbError> ![DB.Write]

PROPAGATE(F91, PROPAGATE(F42, ARG0))
```

`T17`, `F42`, and `F91` are projection-local handles. The compiler service
resolves them to stable graph identities before commit and injects only the
definitions needed for the task.

# Latent ISA examples

This page documents token ABI vectors and semantic shapes. It is not source
code: token IDs are emitted by a compatible model and decoded directly to a
typed graph. Whitespace and comments below exist solely for human inspection.

## Arithmetic

`lil.token/0` encodes a parameter-free `main() -> i32` that returns `20 + 22`
as this token-ID vector:

```text
1, 16, 32, 6164, 32, 6166, 33, 12288, 12289, 34, 12290, 17, 2
```

| IDs | ABI meaning |
| --- | --- |
| `1 … 2` | module begin / module end |
| `16 … 17` | `main() -> i32` begin / function end |
| `32` | append an `i32` constant; the next ID must be an `i32` literal |
| `6164`, `6166` | literals `20`, `22` in the signed-12-bit literal range |
| `33` | append wrapping `i32` addition; the next two IDs must reference live `i32` values |
| `12288`, `12289` | references to local values 0 and 1 |
| `34`, `12290` | return an `i32` value; reference local value 2 |

At the add boundary, the decoder reports the legal reference range
`12288..12289`; it rejects every other token ID. A human can request a
disassembly with `render-token-ids`, but that output is neither parsed nor
saved as source.

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

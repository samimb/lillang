# Latent ISA examples

These are conceptual semantic-token streams, not text source files. Exact
numeric token IDs and decoder states belong to the forthcoming versioned token
ABI; angle-bracket names make the intended form inspectable now.

## Arithmetic

```text
<fn0><i32>
  <const:i32><20>
  <const:i32><22>
  <add.wrapping:i32><value0><value1>
  <return><value2>
```

After `<add.wrapping:i32>`, the decoder permits only existing `i32` values.
After `<return>`, it permits only an `i32` value and then closes the block. The
committed graph is [`arithmetic.json`](arithmetic.json); its human disassembly
is [`arithmetic.lil`](arithmetic.lil).

## Error-propagating composition

```text
<fn1><url><result:user,fetch_error>
  <propagate><json.decode:user><http.get><arg0>
```

`<propagate>` is one semantic operation: its decoder requires a result-producing
child and derives the enclosing error path. It does not ask the model to emit
temporary variables or textual error branches.

## Scoped symbol memory

```text
T17 = User{id:str,name:str}
F42 = get_user(uuid) -> Result<T17,FetchError> ![Net]
F91 = save_user(T17) -> Result<unit,DbError> ![DB.Write]

<fn1><T17><result:unit,DbError>
  <propagate><F91><propagate><F42><arg0>
```

`T17`, `F42`, and `F91` are projection-local handles. The compiler service
resolves them to stable graph identities before commit and injects only the
definitions needed for the task.

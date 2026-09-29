# LIL Wire Protocol v0

**Status:** draft 0.1  
**Scope:** deterministic interchange of Core IR v0 modules and atomic edits.

## 1. Envelope and canonical encoding

The initial wire encoding is canonical JSON encoded as UTF-8. It exists to make fixtures reviewable; it is not the final compact encoding. JSON is not LIL source and is not the canonical program representation: a decoder MUST construct a CPG before semantic validation, rendering, editing, or compilation.

Every document is an envelope:

```json
{
  "protocol": "lil.wire/0",
  "kind": "snapshot | transaction",
  "body": {},
  "optional_metadata": {}
}
```

Canonical JSON requires UTF-8, no insignificant whitespace, lexicographically sorted object keys, decimal integers without exponent notation, lowercase UUIDs, and arrays in the order prescribed by the Core IR schema. A digest is SHA-256 of the canonical envelope bytes, encoded as lowercase hexadecimal.

Unknown fields are rejected everywhere except `optional_metadata`. An unknown required feature is rejected before semantic validation. This avoids silently changing the meaning of a saved program.

The initial JSON mapping for the implemented operation subset is:

```json
{"id":"entry","parameters":[],"operations":[
  {"op":"const","id":"op.answer","type":"i32","value":42},
  {"op":"return","id":"term.return","value":{"operation_id":"op.answer","result_index":0}}
]}
```

This is a wire mapping for the `Block`, `ConstInteger`, `Return`, and
`ValueRef` graph nodes defined by Core IR v0. It is not a textual LIL syntax.

## 2. Snapshots

A snapshot has a Core IR module as its body. `snapshot_digest` means the digest of that full envelope. The compiler records the snapshot digest, compiler build identity, declared target, and dependency source digests in every build manifest.

Determinism means identical snapshot bytes, compiler build identity, target, dependency source digests, linker version, and declared build flags produce byte-identical intermediate objects. Final executable byte identity is only promised where the platform linker and debug-information policy are deterministic; otherwise the compiler promises equivalent semantics and ABI for the same inputs.

## 3. Transactions

```text
Transaction {
  base_snapshot_digest: Digest,
  transaction_id: UUID,
  operations: NonEmptyList<Edit>,
  preconditions: List<Precondition>
}
Edit = create | replace | delete | rename
Precondition = object_digest | declaration_name_unused | reference_absent
```

`create` contains a complete object with a fresh ID. `replace` names an existing object ID and supplies its complete replacement; it cannot change the object ID or object kind. `rename` changes only a declaration name and fails when that name is already in use. `delete` names an object ID and succeeds only if no surviving object references it.

The transaction operation sequence applies to an isolated copy of its base snapshot. Preconditions are evaluated against that copy at the point they appear. The resulting graph must satisfy all Core IR validity rules. On success, it becomes one new snapshot; on failure, no edit is visible.

## 4. Concurrency and conflicts

`commit(base_snapshot_digest, transaction)` succeeds only when `base_snapshot_digest` equals the service's current snapshot digest. A mismatch returns `STALE_BASE` with the current digest and a summary of objects changed since the supplied base when retained history permits it. The service does not automatically merge transactions in v0.

Failures are structured:

```text
Error {
  code: STALE_BASE | PRECONDITION_FAILED | INVALID_EDIT | INVALID_GRAPH,
  object_id: UUID?,
  rule: String?,
  expected: JsonValue?,
  observed: JsonValue?
}
```

## 5. Service surface

The initial service methods are `describe`, `propose`, `commit`, `render`, `build`, and `test`. `propose` executes the same validation as `commit` but produces no snapshot. `render` accepts a snapshot digest and scope; it never renders uncommitted graph state as canonical source. `build` and `test` accept a snapshot digest, ensuring diagnostics and artifacts identify the exact program revision.

Authentication, authorization, repository storage, remote collaboration, and streaming model projections are outside wire protocol v0. They must not alter graph semantics or transaction atomicity when added.

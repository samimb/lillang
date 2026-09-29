# Semantic operator admission v0

**Status:** normative policy for ABI extensions

LIL admits high-level semantic operators only when they reduce whole-task
model information cost without concealing a material program choice. An
operator is an ABI instruction with typed decoder transitions, not a macro
spelling in a human disassembly.

## Admission record

Every proposed operator MUST define:

| Requirement | Required decision |
| --- | --- |
| Identity | Stable ABI IDs/ranges and a feature/version gate. |
| Types | Input slots, result types, polymorphic constraints, and value-handle rules. |
| Effects | Capabilities added, required, transformed, or prohibited. |
| Failure | Error types, conversion rules, partial-result behavior, and propagation. |
| Cancellation | Propagation, cleanup, deadlines, and child-task behavior. |
| Order | Evaluation order, concurrency, retry scheduling, and determinism. |
| Lowering | The graph expansion or backend/runtime contract. |
| Constraints | Exact legal-next-token states and negative decoding cases. |
| Evidence | Fixed tasks and baselines measuring total output, retrieval, retries, tool calls, latency, and review burden. |

An operator MUST be rejected or remain a library-level graph composition when
any material policy remains implicit or its whole-task evidence is absent.

## Initial candidates

These candidates are specified for evaluation, not admitted to `lil.token/0`.

| Candidate | Positive semantic shape | Must reject |
| --- | --- | --- |
| `propagate` | `propagate result<T,E1> as E2 -> T` when an explicit `E1 → E2` conversion exists | a non-`Result` value or unavailable error conversion |
| `retry` | retry a declared idempotent/transient operation with explicit attempts and backoff | non-idempotent effects without a declared compensation/idempotency contract |
| `timeout` | bound a cancellable effectful child and return a declared timeout failure | a child with no cancellation/cleanup contract |
| `parallel.join` | run explicitly independent child computations under a join failure policy | shared mutation, order-dependent effects, or unbounded task creation |
| `transaction` | group declared transactional effects under an isolation and rollback policy | operations outside the transaction capability or without compensation |
| `validate` / `authz` | convert validated/untrusted input into a refined capability/value | unchecked coercion or an omitted rejection path |
| HTTP / SQL / serde | typed requests, queries, and codecs with explicit resource/effect limits | unbounded input, omitted capability, or opaque error behavior |
| logging / metrics | structured observability with declared effect and privacy fields | implicit sensitive-data export or a hidden network effect |

## Decoder examples

The following are semantic projections, not syntax or assigned token IDs.

```text
positive: PROPAGATE(HTTP_GET(url), FetchError.from_http)
negative: PROPAGATE(i32, FetchError.from_http)

positive: TIMEOUT(5s, HTTP_GET(url))
negative: TIMEOUT(5s, non_cancellable_ffi_call())

positive: PARALLEL_JOIN(fetch_avatar(id), fetch_preferences(id))
negative: PARALLEL_JOIN(write_same_buffer(a), write_same_buffer(a))
```

Each admitted operator receives exact token IDs, decoder-state tables, and
positive/negative executable vectors in its own ABI-version extension.

# Implementation epics

GitHub is the live tracker. The current product-direction epic is [#7: Latent
ISA pivot — semantic token ABI and constrained decoding](https://github.com/samimb/lillang/issues/7).
The older graph/backend epics below describe supporting experimental
infrastructure; they no longer define LIL's authoring model.

## Epic: Latent ISA pivot — semantic token ABI and constrained decoding

LIL's primary path is `semantic token IDs → constrained decoder → typed latent
graph → backend`. Human-readable text and JSON snapshots are projections or
transport formats, not source.

**Tracked child issues:** #8 token ABI and decoder states; #9 constrained
decoding prototype; #10 semantic operator criteria; #11 scoped model-memory
projections and handles; #12 whole-task evaluation harness.

**Done when:** a versioned token ABI can construct and edit a typed graph under
decoder constraints, supported semantic operators have explicit type/effect
rules, and a reproducible harness measures whole-task token and validity cost.

**Depends on:** none.

---

The following historical epics remain useful only where they validate the
latent graph and backend layers.

## Epic: Phase 0 — Canonical semantics and conformance

Define and test Core IR v0, deterministic rendering, canonical serialization, and the verifier.

**Done when:** valid and invalid fixture suites exercise every Core IR v0 rule; snapshot digests are stable; rendering is deterministic; and every diagnostic cites an object ID and violated rule.

**Depends on:** none.

## Epic: Phase 1 — Native vertical slice

Compile the Core IR v0 subset to one native target and run executable fixtures.

**Done when:** the Linux x86-64 target compiles scalar arithmetic, branches, loops, structs, `Result`, and direct C calls; object code links; and the test suite executes the fixtures.

**Depends on:** Phase 0.

## Epic: C ABI safety boundary

Define external declarations, manual bindings, ABI checks, safe-wrapper conventions, and cross-language fixture tests.

**Done when:** C scalars, `repr(c)` structs, pointers, opaque handles, callbacks, ownership transfer, static linking, and dynamic linking are tested on every supported target.

**Depends on:** Phase 0 and the native vertical slice.

## Epic: Runtime and backend capabilities

Add ownership, allocator conventions, collections, async I/O, structured tasks, and a minimal hosted runtime.

**Done when:** the documented safe subset rejects invalid ownership and cross-task borrows; cancellation and cleanup tests pass; and a small service can make bounded network and filesystem calls through explicit capabilities.

**Depends on:** Phase 1 and C ABI safety boundary.

## Epic: Model authoring service

Implement scoped descriptions and queries, validated transactions, constrained operation selection, and versioned renderings.

**Done when:** a client can construct and modify a multi-module program solely through the service; stale edits are rejected atomically; and audit output shows unsafe/effectful paths.

**Depends on:** Phase 0; integration can progress alongside later compiler phases.

## Epic: Evidence, hardening, and stabilization

Publish reproducible benchmarks, fuzz decoders and importers, validate target ABIs, and stabilize a versioned release.

**Done when:** public harnesses compare fixed workloads with native baselines; fuzzing and sanitizer jobs run in CI; supported-target ABI fixtures pass; and each published claim links to a measured result.

**Depends on:** all implementation epics.

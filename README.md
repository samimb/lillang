# LIL: an LLM-native systems language

**Status:** design draft 0.1, 29 September 2026  
**Working name:** LIL (Latent Intermediate Language)  
**Audience:** compiler implementers, model and tooling authors, backend developers  
**Normative language:** `MUST`, `SHOULD`, and `MAY` describe intended requirements. This draft is not a claim that an implementation exists.

## 1. Thesis

LIL is a general-purpose, statically typed language whose primary authoring interface is a model operating on structured program edits. Its canonical artifact is a versioned, typed program graph. A textual rendering exists for inspection, debugging, review, and implementation by LLMs. The compiler emits native code and exposes an explicit C ABI boundary.

The aim is to make the *amount of information a model must emit to specify a correct change* small without making the resulting program slow or restricting it to a domain-specific subset. This is a language for services, command-line tools, libraries, agents, and performance-sensitive backend components, including networking, databases, concurrency, and operating-system interfaces.

LIL does not assume that dense syntax alone saves tokens. It measures complete workflows, including retrieved definitions, retries, compiler diagnostics, and patches. It also does not assume that type safety or an SSA graph automatically creates fast machine code. These are hypotheses to test against native-language baselines.

## 2. Design goals and constraints

| Area | Initial requirement |
| --- | --- |
| Runtime | Native executables and libraries with predictable performance; no mandatory garbage collector or VM. |
| Expressiveness | Full backend applications, systems interfaces, generic data structures, asynchronous I/O, and native dependencies. |
| Authoring | Structured create and edit operations with incremental type checking and constrained choices when practical. |
| Reproducibility | Identical canonical input, compiler version, target, and declared dependencies produce equivalent output. |
| Inspection | Every program can be rendered as readable, stable text with types, effects, ownership, source provenance, and FFI boundaries. |
| Safety | Safe core, explicit unsafe boundaries, no implicit I/O, and checked errors. |
| Portability | An implementation starts with a narrow target matrix and expands through explicit target support. |
| Interop | Import C headers and link C libraries through a usable generated interface. |

Initial non-goals: a custom CPU instruction set, a novel cryptography implementation, a new native code generator, and perfect prevention of semantic mistakes by constrained decoding. Human editing of the rendered form can be supported later, but round-trip text editing is not required for the first compiler.

## 3. Representation and versioning

Three layers are distinct:

1. **Canonical program graph (CPG):** a language-defined typed module graph with functions, types, constants, control regions, effects, and dependency references. This is the authoritative source.
2. **Wire format:** a portable, versioned serialization of the CPG and atomic edit transactions. An initial implementation can use a conventional schema format. Compact binary encoding comes after the semantics stabilize.
3. **Model projection:** a context-dependent stream of available operations, symbol handles, type signatures, documentation, and compiler feedback. A tokenizer-specific vocabulary MAY encode frequent operations as single model tokens. Token IDs MUST NOT be the only durable representation.

The graph MUST record a format version, feature set, dependency lock, target assumptions, and compiler language version. Unknown required features cause rejection. Unknown optional metadata can be retained without changing semantics. Semantic identities are derived from module identity and exported symbol identity. Short handles such as `F17` are local to a model session and MUST be resolved before saving. Public interfaces have stable, readable names for linking and diagnostics even when internal locals do not.

Canonical serialization MUST define deterministic ordering and hashing. A graph hash identifies a precise base for an edit; hashes are not a substitute for stable public symbol names. Debug names and comments are metadata, not control-flow or type semantics.

## 4. Core language

### 4.1 Values, types, and control flow

The core is typed SSA: each value has one definition, and control-flow joins take typed block parameters. It contains basic blocks/regions, branches, loops, calls, returns, and explicit effectful operations. A pure DAG alone is insufficient for loops, recursion, exceptions, I/O, and resource cleanup.

Initial value types: fixed-width signed and unsigned integers; `bool`; IEEE floating point; arrays; slices; tuples; structs; tagged unions; pointers and references; function types; opaque external types; `Option<T>`; and `Result<T,E>`. Integers define explicit checked, wrapping, and saturating operations. No implicit narrowing or silent numeric coercion. Layout is explicit for FFI or packed data and otherwise controlled by the compiler. Generic functions and types use monomorphization initially, with code-size measurement.

The core supports higher-order functions, pattern matching lowered to regions, explicit recursion, and closures with compiler-visible captures. Libraries can provide maps, iterators, parsers, HTTP, SQL clients, and other higher-level building blocks; these do not need special compiler opcodes. High-level operations become intrinsics only when a measurable advantage and stable semantics justify them.

### 4.2 Effects and failures

Pure functions can only call pure functions. Effectful functions declare capabilities at their public boundary, for example `Net`, `FS`, `Clock`, `Random`, `Process`, and `UnsafeFFI`. Effects are tracked across calls; the compiler MUST NOT silently drop them. Capability values or handles can further restrict the scope of operations, such as a particular directory or network client.

Recoverable failure is represented with `Result`. A propagation operation forwards an error only when the compiler can prove the conversion is valid. Cancellation and timeouts have explicit semantics. Panics/traps are reserved for violated invariants or declared unrecoverable conditions, never a hidden replacement for ordinary error handling. Allocation failure behavior is part of each allocator API and target policy.

### 4.3 Memory and ownership

Values are immutable by default. The language supports controlled mutation of uniquely owned storage; excluding mutation would make efficient buffers, sockets, and FFI unnecessarily awkward. Resources use ownership and deterministic cleanup. Borrowing is checked statically where possible. Unsafe operations are explicit for raw pointers, ABI crossings, aliasing assertions, and unchecked layout access.

The model-facing interface SHOULD infer moves, borrow lifetimes, and cleanup when there is a unique valid solution. If inference is ambiguous or changes observable behavior, the model must choose explicitly. The compiler cannot assume all heap allocations are stack allocations. Allocation policy is visible through allocator parameters, arenas, owned containers, or an explicit default selected by the application. There is no mandatory tracing GC.

### 4.4 Concurrency

The language has structured tasks, cancellation propagation, and a typed join operation. An async function can suspend around I/O; the runtime or platform backend supplies scheduling and polling. Shared mutation requires an explicit synchronization abstraction or message passing. The type system MUST reject unsound cross-task borrowing and data races within its safe core. Parallel execution is not inferred merely because two graph branches look independent: order, effects, resource contention, and failure semantics matter.

### 4.5 Modules and dependency behavior

Modules export named functions, types, constants, and capabilities. Builds pin dependency versions and source identities. Build scripts and native libraries declare their platform requirements. Public API changes receive stable diagnostics. Incremental compilation uses graph and dependency fingerprints rather than the model's temporary symbol numbers.

## 5. Model authoring protocol

The model edits a repository through a compiler service, not by appending unvalidated bytes to a source file. The service provides:

- `describe(symbol_or_module)`: exact signature, types, effects, ownership, relevant docs, and nearby callers.
- `query(goal, expected_type, scope)`: matching constructors, functions, values, and imports, ranked but not silently substituted.
- `propose(transaction)`: type-check a candidate edit without committing it.
- `commit(base_hash, transaction)`: atomically apply a validated edit or reject a stale base.
- `render(scope)`: produce deterministic human-readable documentation and a diff.
- `build(target)` and `test(selection)`: produce structured diagnostics with graph node IDs and rendered context.

Transactions contain create, replace, reconnect, rename, and delete operations against typed nodes. They declare preconditions and preserve unaffected nodes. The service MUST validate structural integrity, type constraints, effect constraints, ownership, imports, visibility, and control flow before commit. It SHOULD constrain available next operations and operands during generation, but final compiler validation remains authoritative. A well-typed program can still be wrong, insecure, or inefficient.

Model projections are generated for the task and bounded in scope. Every handle is accompanied by enough signature information to disambiguate it. External retrieval is explicit and logged so token accounting includes retrieval. The model can request explanations and diagnostics in a terse or expanded form. These renderings are part of the compiler's public tooling API and are versioned.

### Illustrative rendering, not a committed surface syntax

```text
fn fetch_user(id: UserId, http: &HttpClient, alloc: &Allocator)
  -> Result<User, FetchError> ![Net, Alloc]
  let response = http.get(route_user(id))?
  let body = response.body(limit = 1_MiB, alloc)?
  json.decode<User>(body, alloc)?
```

The graph contains typed calls, ownership edges, error conversions, and control regions. A model might emit a short transaction that references `http.get`, `body`, and `json.decode` by local handles, but the saved program is independent of those handles. The `?` rendering expands to explicit `Result` branches in the core. Resource disposal and error conversion are checked even if they are elided in this view.

## 6. Native compilation and performance

The first compiler pipeline is:

```text
wire decode -> graph validation -> type/effect/ownership checks
            -> typed core IR -> optimization -> LLVM IR
            -> object files -> platform linker -> executable/library
```

LLVM is an initial engineering choice, not a language semantic dependency. Alternative backends can be added if they pass the same conformance suite. The compiler MUST specify evaluation order where effects are observable, integer behavior, memory layout at ABI boundaries, and cleanup. Optimizations may reorder pure operations only when their observable behavior permits it. Debug symbols map machine locations back to graph nodes and human renderings. Compiler errors refer to the smallest relevant node and include the inferred type, expected type, and available repairs.

Performance work begins with a good lowering for loops, slices, structs, generics, inlining, bounds-check elimination, allocation, async state machines, and FFI calls. Every release tracks build time, binary size, peak memory, throughput, and tail latency. A compact model encoding is valuable only if the overall build and generated service are competitive.

## 7. C ABI and native libraries

**Decision for v0.1: C interop is required.** Cheap code generation does not replace years of hardening, platform integration, compatibility work, external review, and maintenance in libraries such as OpenSSL. The initial language should make established libraries usable while allowing a native LIL implementation when justified by testing and ownership of the maintenance burden.

The FFI facility MUST support:

1. Header import using a C frontend to capture declarations, constants, target-specific layout, calling conventions, and macros that can be safely translated. Unsupported macro behavior receives a diagnostic and a wrapper recommendation.
2. Static and dynamic linking with explicit library, version, target, and license metadata.
3. ABI-compatible scalars, structs, unions, pointers, callback functions, opaque handles, and C strings; variadic calls only through a constrained wrapper or explicitly unsafe facility.
4. Imported functions marked `UnsafeFFI` by default. A typed safe wrapper owns pointers, maps error codes, handles cleanup, and specifies thread and lifetime requirements.
5. Integration tests that compile a small C fixture for each supported target and exercise calls in both directions, including callbacks and ownership transfer.

The boundary MUST make it possible to bind OpenSSL without rewriting it. An imported declaration alone does not make calls safe. A standard crypto interface can select a vetted provider through a thin adapter. Native crypto primitives are outside the initial scope. Interop also supports system libraries and existing database, compression, and networking dependencies.

## 8. Runtime and standard library

The runtime is small and replaceable where possible: startup, allocator hooks, panic handling, task scheduling, platform I/O, and debug metadata. Applications can select a target-specific executor. A hosted backend profile supplies sockets, TLS through an established provider, DNS, filesystem, clocks, process control, HTTP, serialization, logging, metrics, testing, and common database interfaces. A minimal profile omits services it does not use.

The standard library exposes explicit limits for untrusted input, including payload sizes, parser nesting, read deadlines, and allocation budgets. APIs show ownership and effects. The package manager locks native and LIL dependencies and supports reproducible builds across the declared target matrix.

## 9. Security and trust boundaries

Model output is untrusted input to the compiler service. Every transaction is validated before it changes the canonical graph. Imported packages and native libraries retain their own trust and supply-chain risks. The compiler records unsafe blocks, FFI call sites, effectful paths, and capability grants for audit. The renderer MUST expose these in review output.

Build and test tools run with declared capabilities. A model cannot gain filesystem or network permissions merely by emitting a node. Diagnostics and external documentation are data, not instructions to the model runtime. Tooling must protect against malformed graphs, excessive expansion, cyclic imports, resource exhaustion, and stale concurrent edits.

## 10. Acceptance criteria and measurement

Claims of parity with Rust, Zig, or Odin are goals, not properties of this document. Measure equivalent programs with identical algorithms, data structures, optimization levels, targets, and dependency policies. Publish the programs and harness.

| Dimension | Measurement |
| --- | --- |
| Generated-code speed | CPU time, allocation count, throughput, and p50/p99 latency for parsers, compression, concurrent HTTP, and database-backed API workloads. |
| Operational footprint | Binary size, startup time, idle/peak RSS, deployment dependencies, and cold-build/incremental-build time. |
| Model efficiency | Total input/output tokens, retrieval tokens, tool calls, retries, wall-clock time, and cost to implement and maintain the same tasks. |
| Correctness | Compile success, conformance, behavioral tests, fuzz findings, sanitizer findings, and defects found after review. |
| Interop | Time to import a C library, wrapper size, runtime overhead, target coverage, and correctness of layout/callback tests. |
| Maintainability | Human review time, quality of diffs/diagnostics, upgrade cost, and ability to change a large service safely. |

First reference application: a small production-style JSON API with routing, TLS, persistent storage, configuration, logging, graceful shutdown, tests, and a C library dependency. It must be written through the model protocol and rendered for human review. A second reference workload should exercise tight loops, buffers, and concurrency so API ergonomics cannot hide poor systems performance.

## 11. Implementation sequence

**Phase 0: semantics and harness.** Define the typed core, graph schema, deterministic serialization, interpreter or verifier, readable renderer, target conventions, and comparison harness. Build small programs and test invalid graph rejection.

**Phase 1: native vertical slice.** Implement functions, branches, loops, structs, `Result`, checked arithmetic, ownership of simple resources, LLVM lowering, linking, C calls, and executable tests. Deliver a CLI and a minimal graph transaction API.

**Phase 2: backend capability.** Add generics, collections, async I/O, structured tasks, native package locking, header import, FFI wrappers, and the hosted standard library. Build the reference API against a real C dependency.

**Phase 3: model integration.** Add typed query, constrained operation selection, transactional patches, scoped projections, and token accounting. Compare models and encodings; add dedicated tokenizer tokens only where whole-task evidence warrants them.

**Phase 4: hardening.** Fuzz decoders and imported headers, test target ABIs, run sanitizers and concurrency tests, stabilize the schema and language version, and publish performance and reliability results.

Each phase has a conformance suite. Include positive execution tests, negative type/effect/ownership tests, round-trip graph serialization, differential tests against the rendered semantics, ABI fixture tests, and benchmarks with fixed harnesses. The compiler should be implemented in whichever established language gives the team the fastest route to a correct, testable implementation; LIL can become self-hosting after it can compile its own toolchain without losing reproducibility.

## 12. Open design decisions

1. **Ownership inference:** how much can be inferred without surprising allocation or lifetime behavior?
2. **Effect granularity:** broad `Net`/`FS` categories versus fine capabilities attached to handles.
3. **Async ABI:** stable public async interfaces across compiler versions and FFI boundaries.
4. **Graph schema:** compact enough for incremental edits while remaining diffable and forward-compatible.
5. **Text editing:** whether a complete lossless textual syntax is worth the implementation cost.
6. **Allocator conventions:** explicit per API, ambient application policy, or a combination.
7. **Errors:** whether to standardize a small error conversion protocol beyond typed `Result`.
8. **Backend choice:** whether LLVM compile times justify a second code generator later.
9. **Model encoding:** which operations deserve vocabulary slots for a particular model/tokenizer, measured end to end.
10. **Ecosystem compatibility:** C first; C++ or Rust integration can initially use a C shim.

## 13. Immediate next deliverables

Write a separate **Core IR specification** with exact node schemas and typing rules; a **wire protocol** with versioning and transactional edits; and a **compiler prototype** that builds an integer/struct/`Result` CLI plus one C fixture. These are the smallest artifacts that can falsify the central design assumptions before investing in a full backend standard library.

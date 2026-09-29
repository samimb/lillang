# Scoped model projections v0

**Status:** implemented prototype contract

A model projection is a task-bounded, read-only view of selected declarations
from one latent graph. It is not source code, a global symbol table, or an
editable rendering.

## Lifecycle

1. A caller requests stable declaration IDs relevant to one task.
2. The compiler service opens a `ScopedProjection` containing only those
   declarations’ compact handles, stable IDs, names for diagnostics, and typed
   signatures/effects.
3. The service records supplied projection and retrieval token counts in its
   `ProjectionLedger`.
4. The model uses compact `u16` handles only inside that projection.
5. Before a graph edit or commit, the service resolves every handle to the
   projection’s stable declaration ID. Unknown handles, duplicate requested
   IDs, and unknown declarations are rejected.
6. The projection is disposed. Its handles must not be reused by another
   projection, revision, or task.

The current Zig API is `openScopedProjection`, `resolveHandle`, and
`ProjectionLedger`. It copies the selected type/effect summary into projection
owned memory, so it cannot expose unrelated graph declarations through a
borrowed mutable graph reference.

## Required rules

- A request MUST identify declarations by stable graph ID, never a display
  name or a prior projection handle.
- A projection MUST reject a repeated requested ID; aliases would make a later
  edit ambiguous.
- Handles start at `1`, are bounded by `u16`, and are meaningful only for the
  projection lifetime.
- The service MUST resolve a handle before it constructs a persistent graph
  edit. Persistent graphs store stable IDs, not model handles.
- `projection_tokens` and `retrieval_tokens` MUST be logged separately to
  preserve whole-task measurement accuracy.
- A disassembly may accompany a projection for review, but it remains a
  read-only context view and cannot introduce or resolve handles.

## Current boundary

This prototype projects declarations and their type/effect summaries. Atomic
multi-edit commit and graph-revision storage are the next service boundary;
they will consume resolved stable IDs and a base graph identity, never the
projection’s local handles.

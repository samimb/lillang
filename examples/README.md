# Examples

Examples construct or manipulate the canonical program graph. They are not
surface-language samples and do not require a model to emit JSON.

## Minimal graph

[`minimal_graph.zig`](minimal_graph.zig) constructs a module containing a
public `main` declaration, one entry block, an `i32` constant, and a typed
return of that constant. It then passes the canonical `Graph` to the semantic
validator.

Run it with:

```sh
zig build example-minimal
```

The `fixtures/` directory is separate: it contains JSON documents solely to
exercise the current wire decoder. The decoder produces the same `Graph` type
used by this example before validation occurs.

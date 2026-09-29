# Examples

Examples construct or manipulate the canonical program graph. They are not
surface-language samples and do not require a model to emit JSON.

## Minimal graph

[`minimal_graph.zig`](minimal_graph.zig) constructs a module containing a
public `main` declaration, one entry block, two `i32` constants, a wrapping
addition, and a typed return. It then passes the canonical `Graph` to the
semantic validator.

Run it with:

```sh
zig build example-minimal
```

The same graph can be evaluated through the wire adapter without treating JSON
as source:

```sh
zig build run -- eval fixtures/valid/minimal-macos.json
```

The `fixtures/` directory is separate: it contains JSON documents solely to
exercise the current wire decoder. The decoder produces the same `Graph` type
used by this example before validation occurs.

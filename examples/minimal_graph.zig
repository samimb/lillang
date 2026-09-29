const std = @import("std");
const lil = @import("lil");

// This is a canonical graph constructed directly in code. It is not parsed
// from JSON and demonstrates the representation models and tools work with.
const entry_blocks = [_]lil.Block{.{ .id = "block.entry" }};

const declarations = [_]lil.Declaration{.{ .function_decl = .{
    .id = "fn.main",
    .name = "main",
    .visibility = .public,
    .parameters = &.{},
    .result = .i32,
    .effects = &.{},
    .body = .{
        .entry = "block.entry",
        .blocks = &entry_blocks,
    },
} }};

const program = lil.Graph{
    .id = "example.minimal",
    .target = .aarch64_macos,
    .declarations = &declarations,
};

pub fn main(_: std.process.Init) !void {
    try lil.validateGraph(program, std.heap.page_allocator);
    std.debug.print("valid graph: {s} ({s})\n", .{ program.id, program.target.wireName() });
}

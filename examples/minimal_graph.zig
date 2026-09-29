const std = @import("std");
const lil = @import("lil");

// This is a canonical graph constructed directly in code. It is not parsed
// from JSON and demonstrates the representation models and tools work with.
const entry_operations = [_]lil.Operation{
    .{ .const_integer = .{ .id = "op.left", .type = .i32, .value = 20 } },
    .{ .const_integer = .{ .id = "op.right", .type = .i32, .value = 22 } },
    .{ .wrapping_add = .{
        .id = "op.answer",
        .type = .i32,
        .left = .{ .operation_id = "op.left", .result_index = 0 },
        .right = .{ .operation_id = "op.right", .result_index = 0 },
    } },
    .{ .return_value = .{
        .id = "term.return",
        .value = .{ .operation_id = "op.answer", .result_index = 0 },
    } },
};

const entry_blocks = [_]lil.Block{.{
    .id = "block.entry",
    .parameters = &.{},
    .operations = &entry_operations,
}};

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
    .dependencies = &.{},
    .declarations = &declarations,
};

pub fn main(_: std.process.Init) !void {
    try lil.validateGraph(program, std.heap.page_allocator);
    std.debug.print("valid graph: {s} ({s})\n", .{ program.id, program.target.wireName() });
}

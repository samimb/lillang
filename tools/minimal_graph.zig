const std = @import("std");
const lil = @import("lil");

// Bootstrap-tooling example: constructs a canonical graph directly in Zig.
const operations = [_]lil.Operation{
    .{ .const_integer = .{ .id = "op.answer", .type = .i32, .value = 42 } },
    .{ .return_value = .{ .id = "term.return", .value = .{ .operation_id = "op.answer", .result_index = 0 } } },
};
const blocks = [_]lil.Block{.{ .id = "entry", .parameters = &.{}, .operations = &operations }};
const declarations = [_]lil.Declaration{.{ .function_decl = .{
    .id = "fn.main", .name = "main", .visibility = .public, .parameters = &.{}, .result = .i32, .effects = &.{},
    .body = .{ .entry = "entry", .blocks = &blocks },
} }};
const program = lil.Graph{ .id = "tool.minimal", .target = .aarch64_macos, .dependencies = &.{}, .declarations = &declarations };

pub fn main(_: std.process.Init) !void {
    try lil.validateGraph(program, std.heap.page_allocator);
    std.debug.print("valid graph: {s} ({s})\n", .{ program.id, program.target.wireName() });
}

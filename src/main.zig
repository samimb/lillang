const std = @import("std");
const lil = @import("lil");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return usage();

    const token_ids = try parseTokenIds(allocator, args[2]);
    defer allocator.free(token_ids);

    if (std.mem.eql(u8, args[1], "legal-next-token-ids")) {
        var decoder = try lil.SemanticDecoder.init(allocator, .aarch64_macos, token_ids.len);
        defer decoder.deinit();
        for (token_ids) |id| try decoder.push(id);
        return writeConstraint(init, decoder.nextConstraint());
    }

    var program = lil.decodeTokenIds(allocator, .aarch64_macos, token_ids) catch |err| {
        std.debug.print("token ABI rejected stream: {t}\n", .{err});
        return err;
    };
    defer program.deinit();

    if (std.mem.eql(u8, args[1], "check-token-ids")) {
        std.debug.print("valid LIL {s} token stream\n", .{lil.token_abi_version});
    } else if (std.mem.eql(u8, args[1], "render-token-ids")) {
        const rendered = try lil.renderGraph(allocator, program.graph);
        defer allocator.free(rendered);
        try writeStdout(init, rendered);
    } else if (std.mem.eql(u8, args[1], "eval-token-ids")) {
        const result = try lil.evaluateMain(program.graph, allocator);
        var output: std.Io.Writer.Allocating = .init(allocator);
        defer output.deinit();
        try result.format(&output.writer);
        try output.writer.writeAll("\n");
        try writeStdout(init, output.written());
    } else if (std.mem.eql(u8, args[1], "lower-token-ids")) {
        const llvm_ir = try lil.lowerMainToLlvm(allocator, program.graph);
        defer allocator.free(llvm_ir);
        try writeStdout(init, llvm_ir);
    } else {
        return usage();
    }
}

fn parseTokenIds(allocator: std.mem.Allocator, input: []const u8) ![]lil.TokenId {
    if (std.mem.eql(u8, input, "-")) return allocator.alloc(lil.TokenId, 0);
    var ids: std.ArrayList(lil.TokenId) = .empty;
    defer ids.deinit(allocator);
    var parts = std.mem.splitScalar(u8, input, ',');
    while (parts.next()) |part| {
        if (part.len == 0) return error.InvalidTokenList;
        try ids.append(allocator, try std.fmt.parseInt(lil.TokenId, part, 0));
    }
    return ids.toOwnedSlice(allocator);
}

fn writeConstraint(init: std.process.Init, constraint: lil.NextTokenConstraint) !void {
    var output: std.Io.Writer.Allocating = .init(init.arena.allocator());
    defer output.deinit();
    switch (constraint) {
        .exact => |ids| {
            try output.writer.writeAll("exact token IDs: ");
            for (ids, 0..) |id, index| {
                if (index != 0) try output.writer.writeAll(",");
                try output.writer.print("{d}", .{id});
            }
            try output.writer.writeAll("\n");
        },
        .i32_literal => try output.writer.print("i32 literal token IDs: {d}..{d}\n", .{
            lil.TokenAbi.literal_i32_base,
            lil.TokenAbi.literal_i32_base + lil.TokenAbi.literal_i32_count - 1,
        }),
        .i32_value_ref => |count| {
            if (count == 0) {
                try output.writer.writeAll("no i32 value references are currently legal\n");
            } else {
                try output.writer.print("i32 value-reference token IDs: {d}..{d}\n", .{
                    lil.TokenAbi.value_ref_base,
                    lil.TokenAbi.value_ref_base + count - 1,
                });
            }
        },
        .terminal => try output.writer.writeAll("program is complete; no next token is legal\n"),
    }
    try writeStdout(init, output.written());
}

fn writeStdout(init: std.process.Init, bytes: []const u8) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    try stdout.interface.writeAll(bytes);
    try stdout.interface.flush();
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        "usage: lil <check-token-ids|render-token-ids|eval-token-ids|lower-token-ids|legal-next-token-ids> <comma-separated-u16-ids|->\n",
        .{},
    );
    return error.InvalidArguments;
}

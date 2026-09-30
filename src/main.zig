const std = @import("std");
const lil = @import("lil");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len == 5 and std.mem.eql(u8, args[1], "pack") and std.mem.eql(u8, args[3], "-o")) {
        const token_ids = try parseTokenIds(allocator, args[2]);
        defer allocator.free(token_ids);
        const bytes = try lil.encodeFunctionGraphV1File(allocator, token_ids);
        defer allocator.free(bytes);
        return std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[4], .data = bytes });
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "debug")) {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], allocator, .limited(16 * 1024 * 1024));
        defer allocator.free(bytes);
        var program = try lil.decodeFunctionGraphV1File(allocator, bytes, .aarch64_macos);
        defer program.deinit();
        const rendered = try lil.renderGraph(allocator, program.graph);
        defer allocator.free(rendered);
        return writeStdout(init, rendered);
    }
    if (args.len == 5 and std.mem.eql(u8, args[1], "build") and std.mem.eql(u8, args[3], "-o")) {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], allocator, .limited(16 * 1024 * 1024));
        defer allocator.free(bytes);
        var program = try lil.decodeFunctionGraphV1File(allocator, bytes, .aarch64_macos);
        defer program.deinit();
        const llvm_ir = try lil.lowerFunctionGraphV1ToLlvm(allocator, program.graph);
        defer allocator.free(llvm_ir);
        return linkFunctionGraph(init, allocator, llvm_ir, args[4]);
    }
    if (args.len != 3) return usage();

    const token_ids = try parseTokenIds(allocator, args[2]);
    defer allocator.free(token_ids);

    if (std.mem.eql(u8, args[1], "lower-function-graph-v1")) {
        var program = try lil.decodeFunctionGraphV1(allocator, .aarch64_macos, token_ids);
        defer program.deinit();
        const llvm_ir = try lil.lowerFunctionGraphV1ToLlvm(allocator, program.graph);
        defer allocator.free(llvm_ir);
        return writeStdout(init, llvm_ir);
    }

    if (std.mem.eql(u8, args[1], "legal-next-token-ids")) {
        var decoder = try lil.SemanticDecoder.init(allocator, .aarch64_macos, token_ids.len);
        defer decoder.deinit();
        for (token_ids) |id| try decoder.push(id);
        return writeConstraint(init, decoder.nextConstraint());
    }

    var program = lil.decodeTokenIds(allocator, .aarch64_macos, token_ids) catch |err| {
        if (try lil.diagnoseTokenIds(allocator, .aarch64_macos, token_ids)) |diagnostic| {
            if (diagnostic.received) |received| {
                std.debug.print(
                    "token ABI rejected at offset {d}: received {d}, state {t}, expected {t}, target {s}: {t}\n",
                    .{ diagnostic.token_offset, received, diagnostic.state, std.meta.activeTag(diagnostic.expected), diagnostic.target.wireName(), diagnostic.failure },
                );
            } else {
                std.debug.print(
                    "token ABI rejected at end of stream: state {t}, expected {t}, target {s}: {t}\n",
                    .{ diagnostic.state, std.meta.activeTag(diagnostic.expected), diagnostic.target.wireName(), diagnostic.failure },
                );
            }
        } else {
            std.debug.print("token ABI rejected stream: {t}\n", .{err});
        }
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

fn linkFunctionGraph(init: std.process.Init, allocator: std.mem.Allocator, llvm_ir: []const u8, output_path: []const u8) !void {
    const ll_path = try std.fmt.allocPrint(allocator, "{s}.lil-tmp.ll", .{output_path});
    const c_path = try std.fmt.allocPrint(allocator, "{s}.lil-tmp.c", .{output_path});
    defer {
        std.Io.Dir.cwd().deleteFile(init.io, ll_path) catch {};
        std.Io.Dir.cwd().deleteFile(init.io, c_path) catch {};
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = ll_path, .data = llvm_ir });
    const wrapper = "#include <stdint.h>\nextern int64_t lil_entry(int64_t, int64_t);\nint main(void) { return lil_entry(20, 22) == 42 ? 0 : 1; }\n";
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = c_path, .data = wrapper });
    const emit = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{output_path});
    const result = try std.process.run(allocator, init.io, .{ .argv = &.{ "zig", "build-exe", "-lc", ll_path, c_path, emit }, .stderr_limit = .limited(64 * 1024) });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) {
        std.debug.print("link failed: {s}\n", .{result.stderr});
        return error.LinkFailed;
    }
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        "usage: lil pack <comma-separated-u16-ids> -o <file.lil>\n       lil debug <file.lil>\n       lil build <file.lil> -o <executable>\n       lil <lower-function-graph-v1|check-token-ids|render-token-ids|eval-token-ids|lower-token-ids|legal-next-token-ids> <comma-separated-u16-ids|->\n",
        .{},
    );
    return error.InvalidArguments;
}

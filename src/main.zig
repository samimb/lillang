const std = @import("std");
const lil = @import("lil");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) {
        std.debug.print("usage: lil <check|render|eval|encode|digest> <snapshot.json>\n", .{});
        return error.InvalidArguments;
    }

    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], allocator, .limited(16 * 1024 * 1024));
    var snapshot = lil.decodeJsonSnapshot(allocator, bytes) catch |err| {
        std.debug.print("invalid wire snapshot: {t}\n", .{err});
        return err;
    };
    defer snapshot.deinit();
    if (try lil.diagnoseGraph(snapshot.graph, allocator)) |diagnostic| {
        std.debug.print("invalid canonical graph: {t} at {s}: {s}\n", .{ diagnostic.code, diagnostic.object_id, diagnostic.rule });
        return diagnostic.code;
    }
    if (std.mem.eql(u8, args[1], "check")) {
        std.debug.print("valid LIL Core IR v0 snapshot\n", .{});
    } else if (std.mem.eql(u8, args[1], "render")) {
        const rendered = try lil.renderGraph(allocator, snapshot.graph);
        var stdout_buffer: [4096]u8 = undefined;
        var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
        try stdout.interface.writeAll(rendered);
        try stdout.interface.flush();
    } else if (std.mem.eql(u8, args[1], "eval")) {
        const result = try lil.evaluateMain(snapshot.graph, allocator);
        var stdout_buffer: [4096]u8 = undefined;
        var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
        try result.format(&stdout.interface);
        try stdout.interface.writeAll("\n");
        try stdout.interface.flush();
    } else if (std.mem.eql(u8, args[1], "encode")) {
        const encoded = try lil.encodeJsonSnapshot(allocator, snapshot.graph);
        var stdout_buffer: [4096]u8 = undefined;
        var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
        try stdout.interface.writeAll(encoded);
        try stdout.interface.writeAll("\n");
        try stdout.interface.flush();
    } else if (std.mem.eql(u8, args[1], "digest")) {
        const encoded = try lil.encodeJsonSnapshot(allocator, snapshot.graph);
        const digest = lil.snapshotDigest(encoded);
        var stdout_buffer: [4096]u8 = undefined;
        var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
        try stdout.interface.writeAll(&digest);
        try stdout.interface.writeAll("\n");
        try stdout.interface.flush();
    } else {
        std.debug.print("usage: lil <check|render|eval|encode|digest> <snapshot.json>\n", .{});
        return error.InvalidArguments;
    }
}

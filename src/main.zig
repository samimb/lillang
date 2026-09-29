const std = @import("std");
const lil = @import("lil");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3 or !std.mem.eql(u8, args[1], "check")) {
        std.debug.print("usage: lil check <snapshot.json>\n", .{});
        return error.InvalidArguments;
    }

    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], allocator, .limited(16 * 1024 * 1024));
    lil.validateSnapshot(allocator, bytes) catch |err| {
        std.debug.print("invalid snapshot: {t}\n", .{err});
        return err;
    };
    std.debug.print("valid LIL Core IR v0 snapshot\n", .{});
}

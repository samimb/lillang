const std = @import("std");
const lil = @import("lil");

const Task = struct {
    id: []const u8,
    token_ids: []const lil.TokenId,
    native_baseline: []const u8,
};

const arithmetic_tokens = [_]lil.TokenId{
    1, 16, 32, 6164, 32, 6166, 33, 12288, 12289, 34, 12290, 17, 2,
};

const tasks = [_]Task{.{
    .id = "arithmetic.create",
    .token_ids = &arithmetic_tokens,
    .native_baseline = "pub fn main() i32 { return 20 + 22; }\n",
}};

/// Emits tab-separated records so an experiment runner can join model/tokenizer
/// observations without conflating them with decoder or backend behavior. The
/// fixture model/tokenizer values deliberately mean “not sampled from a model”.
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    var stdout_buffer: [4096]u8 = undefined;
    var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const writer = &stdout.interface;
    try writer.writeAll("task\tmodel\ttokenizer\tabi\tcompiler\tbackend\tsemantic_output_tokens\tnative_baseline_bytes\tretrieval_tokens\tconstrained_retries\ttool_calls\tdecode_ns\tlower_ns\n");

    for (tasks) |task| {
        const decode_start = std.Io.Timestamp.now(init.io, .awake);
        var program = try lil.decodeTokenIds(allocator, .aarch64_macos, task.token_ids);
        defer program.deinit();
        const decode_ns = decode_start.untilNow(init.io, .awake).nanoseconds;

        const lower_start = std.Io.Timestamp.now(init.io, .awake);
        const llvm_ir = try lil.lowerMainToLlvm(allocator, program.graph);
        defer allocator.free(llvm_ir);
        const lower_ns = lower_start.untilNow(init.io, .awake).nanoseconds;

        try writer.print("{s}\tfixture\tfixture\t{s}\tzig-prototype\tllvm-ir\t{d}\t{d}\t0\t0\t0\t{d}\t{d}\n", .{
            task.id,
            program.abi_version,
            program.token_count,
            task.native_baseline.len,
            decode_ns,
            lower_ns,
        });
    }
    try stdout.interface.flush();
}

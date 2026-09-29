const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lil = b.addModule("lil", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "lil",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "lil", .module = lil }},
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Run the LIL command-line tool");
    run_step.dependOn(&run.step);

    const tests = b.addTest(.{ .root_module = lil });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run Core IR validator tests");
    test_step.dependOn(&run_tests.step);

    const minimal_example = b.addExecutable(.{
        .name = "lil-minimal-graph",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/minimal_graph.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "lil", .module = lil }},
        }),
    });
    const run_minimal_example = b.addRunArtifact(minimal_example);
    const example_step = b.step("example-minimal", "Validate the graph-native minimal example");
    example_step.dependOn(&run_minimal_example.step);
}

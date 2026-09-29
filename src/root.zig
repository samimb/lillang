const std = @import("std");

pub const format_version = "lil.cpg/0";
pub const language_version = "0.1";

pub const ValidationError = error{
    InvalidEnvelope,
    MissingField,
    InvalidField,
    UnsupportedTarget,
    DuplicateDeclarationId,
    DuplicateDeclarationName,
};

/// Validates the structural, versioning, and identity rules that make a
/// snapshot safe to pass to later semantic validation. SSA, operation typing,
/// and ownership validation are intentionally separate future passes.
pub fn validateSnapshot(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();

    const envelope = try object(parsed.value);
    try expectStringEqual(try required(envelope, "protocol"), "lil.wire/0");
    try expectStringEqual(try required(envelope, "kind"), "snapshot");
    _ = try object(try required(envelope, "optional_metadata"));

    const module = try object(try required(envelope, "body"));
    try expectStringEqual(try required(module, "format_version"), format_version);
    try expectStringEqual(try required(module, "language_version"), language_version);
    try validateTarget(try string(try required(module, "target")));
    _ = try string(try required(module, "id"));
    _ = try array(try required(module, "dependencies"));

    const declarations = try array(try required(module, "declarations"));
    var ids = std.StringHashMap(void).init(allocator);
    defer ids.deinit();
    var names = std.StringHashMap(void).init(allocator);
    defer names.deinit();

    for (declarations.items) |declaration| {
        const item = try object(declaration);
        const id = try string(try required(item, "id"));
        const name = try string(try required(item, "name"));
        if (ids.contains(id)) return error.DuplicateDeclarationId;
        if (names.contains(name)) return error.DuplicateDeclarationName;
        try ids.put(id, {});
        try names.put(name, {});

        const kind = try string(try required(item, "kind"));
        if (std.mem.eql(u8, kind, "struct")) {
            try validateStruct(item);
        } else if (std.mem.eql(u8, kind, "function")) {
            try validateFunction(item);
        } else if (std.mem.eql(u8, kind, "external_function")) {
            try validateExternalFunction(item);
        } else {
            return error.InvalidField;
        }
    }
}

fn validateTarget(target: []const u8) ValidationError!void {
    const supported = [_][]const u8{
        "aarch64-macos-none",
        "x86_64-macos-none",
        "x86_64-linux-gnu",
    };
    for (supported) |candidate| {
        if (std.mem.eql(u8, target, candidate)) return;
    }
    return error.UnsupportedTarget;
}

fn validateStruct(declaration: std.json.ObjectMap) !void {
    const repr = try string(try required(declaration, "repr"));
    if (!std.mem.eql(u8, repr, "native") and !std.mem.eql(u8, repr, "c")) return error.InvalidField;

    const fields = try array(try required(declaration, "fields"));
    for (fields.items) |field| {
        const item = try object(field);
        _ = try string(try required(item, "name"));
        try validateType(try required(item, "type"));
    }
}

fn validateFunction(declaration: std.json.ObjectMap) !void {
    const visibility = try string(try required(declaration, "visibility"));
    if (!std.mem.eql(u8, visibility, "private") and !std.mem.eql(u8, visibility, "public")) return error.InvalidField;

    const parameters = try array(try required(declaration, "parameters"));
    for (parameters.items) |parameter| {
        const item = try object(parameter);
        _ = try string(try required(item, "name"));
        try validateType(try required(item, "type"));
    }
    try validateType(try required(declaration, "result"));
    try validateEffects(try required(declaration, "effects"));
    const body = try object(try required(declaration, "body"));
    _ = try string(try required(body, "entry"));
    _ = try array(try required(body, "blocks"));
}

fn validateExternalFunction(declaration: std.json.ObjectMap) !void {
    _ = try string(try required(declaration, "c_symbol"));
    _ = try string(try required(declaration, "calling_convention"));
    _ = try string(try required(declaration, "library"));
    const parameters = try array(try required(declaration, "parameters"));
    for (parameters.items) |parameter| try validateType(parameter);
    try validateType(try required(declaration, "result"));
}

fn validateEffects(value: std.json.Value) !void {
    const effects = try array(value);
    for (effects.items) |effect| {
        try expectStringEqual(effect, "UnsafeFFI");
    }
}

fn validateType(value: std.json.Value) !void {
    const name = try string(value);
    const allowed = [_][]const u8{
        "unit", "bool", "i8",  "i16", "i32", "i64", "u8",
        "u16",  "u32",  "u64", "f32", "f64",
    };
    for (allowed) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return;
    }
    return error.InvalidField;
}

fn required(item: std.json.ObjectMap, field: []const u8) ValidationError!std.json.Value {
    return item.get(field) orelse error.MissingField;
}

fn object(value: std.json.Value) ValidationError!std.json.ObjectMap {
    return switch (value) {
        .object => |item| item,
        else => error.InvalidField,
    };
}

fn array(value: std.json.Value) ValidationError!std.json.Array {
    return switch (value) {
        .array => |item| item,
        else => error.InvalidField,
    };
}

fn string(value: std.json.Value) ValidationError![]const u8 {
    return switch (value) {
        .string => |item| item,
        else => error.InvalidField,
    };
}

fn expectStringEqual(value: std.json.Value, expected: []const u8) ValidationError!void {
    if (!std.mem.eql(u8, try string(value), expected)) return error.InvalidField;
}

test "accepts a minimal macOS snapshot" {
    const snapshot =
        \\{"protocol":"lil.wire/0","kind":"snapshot","optional_metadata":{},"body":{"id":"module.main","format_version":"lil.cpg/0","language_version":"0.1","target":"aarch64-macos-none","dependencies":[],"declarations":[{"kind":"function","id":"fn.main","name":"main","visibility":"public","parameters":[],"result":"i32","effects":[],"body":{"entry":"entry","blocks":[]}}]}}
    ;
    try validateSnapshot(std.testing.allocator, snapshot);
}

test "rejects an unsupported target" {
    const snapshot =
        \\{"protocol":"lil.wire/0","kind":"snapshot","optional_metadata":{},"body":{"id":"module.main","format_version":"lil.cpg/0","language_version":"0.1","target":"wasm32-freestanding","dependencies":[],"declarations":[]}}
    ;
    try std.testing.expectError(error.UnsupportedTarget, validateSnapshot(std.testing.allocator, snapshot));
}

test "rejects duplicate declaration names" {
    const snapshot =
        \\{"protocol":"lil.wire/0","kind":"snapshot","optional_metadata":{},"body":{"id":"module.main","format_version":"lil.cpg/0","language_version":"0.1","target":"aarch64-macos-none","dependencies":[],"declarations":[{"kind":"struct","id":"type.one","name":"Thing","repr":"native","fields":[]},{"kind":"struct","id":"type.two","name":"Thing","repr":"native","fields":[]}]}}
    ;
    try std.testing.expectError(error.DuplicateDeclarationName, validateSnapshot(std.testing.allocator, snapshot));
}

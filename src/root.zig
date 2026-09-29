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
    DuplicateBlockId,
    MissingEntryBlock,
    DuplicateOperationId,
    MissingTerminator,
    UnexpectedTerminator,
    UnknownValue,
    InvalidResultIndex,
    ReturnTypeMismatch,
    ConstantOutOfRange,
};

/// The canonical program representation. It is independent of JSON, rendering
/// syntax, model handles, and storage format.
pub const Graph = struct {
    id: []const u8,
    target: Target,
    declarations: []const Declaration,
};

pub const Target = enum {
    aarch64_macos,
    x86_64_macos,
    x86_64_linux,

    pub fn wireName(self: Target) []const u8 {
        return switch (self) {
            .aarch64_macos => "aarch64-macos-none",
            .x86_64_macos => "x86_64-macos-none",
            .x86_64_linux => "x86_64-linux-gnu",
        };
    }
};

pub const ScalarType = enum {
    unit,
    boolean,
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    f32,
    f64,
};

pub const Visibility = enum { private, public };
pub const Effect = enum { unsafe_ffi };

pub const Parameter = struct { name: []const u8, type: ScalarType };
pub const Field = struct { name: []const u8, type: ScalarType };
pub const Representation = enum { native, c };

pub const StructDeclaration = struct {
    id: []const u8,
    name: []const u8,
    repr: Representation,
    fields: []const Field,
};

pub const BlockParameter = struct { id: []const u8, type: ScalarType };

pub const ValueRef = struct {
    operation_id: []const u8,
    result_index: u32,
};

pub const IntegerConstant = struct {
    id: []const u8,
    type: ScalarType,
    value: i64,
};

pub const Return = struct {
    id: []const u8,
    value: ValueRef,
};

pub const Operation = union(enum) {
    const_integer: IntegerConstant,
    return_value: Return,

    pub fn id(self: Operation) []const u8 {
        return switch (self) {
            .const_integer => |value| value.id,
            .return_value => |value| value.id,
        };
    }

    pub fn isTerminator(self: Operation) bool {
        return switch (self) {
            .return_value => true,
            else => false,
        };
    }
};

pub const Block = struct {
    id: []const u8,
    parameters: []const BlockParameter,
    operations: []const Operation,
};

pub const FunctionBody = struct {
    entry: []const u8,
    blocks: []const Block,
};

pub const FunctionDeclaration = struct {
    id: []const u8,
    name: []const u8,
    visibility: Visibility,
    parameters: []const Parameter,
    result: ScalarType,
    effects: []const Effect,
    body: FunctionBody,
};

pub const ExternalFunctionDeclaration = struct {
    id: []const u8,
    name: []const u8,
    c_symbol: []const u8,
    calling_convention: []const u8,
    library: []const u8,
    parameters: []const ScalarType,
    result: ScalarType,
};

pub const Declaration = union(enum) {
    struct_decl: StructDeclaration,
    function_decl: FunctionDeclaration,
    external_function_decl: ExternalFunctionDeclaration,

    pub fn id(self: Declaration) []const u8 {
        return switch (self) {
            .struct_decl => |value| value.id,
            .function_decl => |value| value.id,
            .external_function_decl => |value| value.id,
        };
    }

    pub fn name(self: Declaration) []const u8 {
        return switch (self) {
            .struct_decl => |value| value.name,
            .function_decl => |value| value.name,
            .external_function_decl => |value| value.name,
        };
    }
};

/// Owns the memory for a graph decoded from a wire representation. Graphs
/// constructed directly in Zig can use static or caller-owned memory instead.
pub const DecodedSnapshot = struct {
    arena: std.heap.ArenaAllocator,
    graph: Graph,

    pub fn deinit(self: *DecodedSnapshot) void {
        self.arena.deinit();
    }
};

/// Decodes v0 JSON into the canonical graph. JSON ends at this adapter.
pub fn decodeJsonSnapshot(backing_allocator: std.mem.Allocator, bytes: []const u8) !DecodedSnapshot {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    const document = try std.json.parseFromSliceLeaky(std.json.Value, allocator, bytes, .{});
    const envelope = try object(document);
    try expectStringEqual(try required(envelope, "protocol"), "lil.wire/0");
    try expectStringEqual(try required(envelope, "kind"), "snapshot");
    _ = try object(try required(envelope, "optional_metadata"));

    const module = try object(try required(envelope, "body"));
    try expectStringEqual(try required(module, "format_version"), format_version);
    try expectStringEqual(try required(module, "language_version"), language_version);
    _ = try array(try required(module, "dependencies"));

    return .{ .arena = arena, .graph = try decodeGraph(allocator, module) };
}

fn decodeGraph(allocator: std.mem.Allocator, module: std.json.ObjectMap) !Graph {
    const declarations_json = try array(try required(module, "declarations"));
    const declarations = try allocator.alloc(Declaration, declarations_json.items.len);
    for (declarations_json.items, 0..) |item, index| {
        declarations[index] = try decodeDeclaration(allocator, try object(item));
    }
    return .{
        .id = try duplicateString(allocator, try string(try required(module, "id"))),
        .target = try decodeTarget(try string(try required(module, "target"))),
        .declarations = declarations,
    };
}

fn decodeDeclaration(allocator: std.mem.Allocator, item: std.json.ObjectMap) !Declaration {
    const kind = try string(try required(item, "kind"));
    if (std.mem.eql(u8, kind, "struct")) return .{ .struct_decl = try decodeStruct(allocator, item) };
    if (std.mem.eql(u8, kind, "function")) return .{ .function_decl = try decodeFunction(allocator, item) };
    if (std.mem.eql(u8, kind, "external_function")) return .{ .external_function_decl = try decodeExternalFunction(allocator, item) };
    return error.InvalidField;
}

fn decodeStruct(allocator: std.mem.Allocator, item: std.json.ObjectMap) !StructDeclaration {
    const fields_json = try array(try required(item, "fields"));
    const fields = try allocator.alloc(Field, fields_json.items.len);
    for (fields_json.items, 0..) |value, index| {
        const field = try object(value);
        fields[index] = .{
            .name = try duplicateString(allocator, try string(try required(field, "name"))),
            .type = try decodeType(try required(field, "type")),
        };
    }
    return .{
        .id = try duplicateString(allocator, try string(try required(item, "id"))),
        .name = try duplicateString(allocator, try string(try required(item, "name"))),
        .repr = try decodeRepresentation(try string(try required(item, "repr"))),
        .fields = fields,
    };
}

fn decodeFunction(allocator: std.mem.Allocator, item: std.json.ObjectMap) !FunctionDeclaration {
    const body_json = try object(try required(item, "body"));
    return .{
        .id = try duplicateString(allocator, try string(try required(item, "id"))),
        .name = try duplicateString(allocator, try string(try required(item, "name"))),
        .visibility = try decodeVisibility(try string(try required(item, "visibility"))),
        .parameters = try decodeParameters(allocator, try array(try required(item, "parameters"))),
        .result = try decodeType(try required(item, "result")),
        .effects = try decodeEffects(allocator, try array(try required(item, "effects"))),
        .body = try decodeBody(allocator, body_json),
    };
}

fn decodeExternalFunction(allocator: std.mem.Allocator, item: std.json.ObjectMap) !ExternalFunctionDeclaration {
    const parameters_json = try array(try required(item, "parameters"));
    const parameters = try allocator.alloc(ScalarType, parameters_json.items.len);
    for (parameters_json.items, 0..) |parameter, index| parameters[index] = try decodeType(parameter);
    return .{
        .id = try duplicateString(allocator, try string(try required(item, "id"))),
        .name = try duplicateString(allocator, try string(try required(item, "name"))),
        .c_symbol = try duplicateString(allocator, try string(try required(item, "c_symbol"))),
        .calling_convention = try duplicateString(allocator, try string(try required(item, "calling_convention"))),
        .library = try duplicateString(allocator, try string(try required(item, "library"))),
        .parameters = parameters,
        .result = try decodeType(try required(item, "result")),
    };
}

fn decodeParameters(allocator: std.mem.Allocator, parameters_json: std.json.Array) ![]const Parameter {
    const parameters = try allocator.alloc(Parameter, parameters_json.items.len);
    for (parameters_json.items, 0..) |value, index| {
        const parameter = try object(value);
        parameters[index] = .{
            .name = try duplicateString(allocator, try string(try required(parameter, "name"))),
            .type = try decodeType(try required(parameter, "type")),
        };
    }
    return parameters;
}

fn decodeEffects(allocator: std.mem.Allocator, effects_json: std.json.Array) ![]const Effect {
    const effects = try allocator.alloc(Effect, effects_json.items.len);
    for (effects_json.items, 0..) |value, index| {
        try expectStringEqual(value, "UnsafeFFI");
        effects[index] = .unsafe_ffi;
    }
    return effects;
}

fn decodeBody(allocator: std.mem.Allocator, item: std.json.ObjectMap) !FunctionBody {
    const blocks_json = try array(try required(item, "blocks"));
    const blocks = try allocator.alloc(Block, blocks_json.items.len);
    for (blocks_json.items, 0..) |value, index| {
        const block = try object(value);
        blocks[index] = try decodeBlock(allocator, block);
    }
    return .{
        .entry = try duplicateString(allocator, try string(try required(item, "entry"))),
        .blocks = blocks,
    };
}

fn decodeBlock(allocator: std.mem.Allocator, item: std.json.ObjectMap) !Block {
    const parameters_json = try array(try required(item, "parameters"));
    const parameters = try allocator.alloc(BlockParameter, parameters_json.items.len);
    for (parameters_json.items, 0..) |value, index| {
        const parameter = try object(value);
        parameters[index] = .{
            .id = try duplicateString(allocator, try string(try required(parameter, "id"))),
            .type = try decodeType(try required(parameter, "type")),
        };
    }

    const operations_json = try array(try required(item, "operations"));
    const operations = try allocator.alloc(Operation, operations_json.items.len);
    for (operations_json.items, 0..) |value, index| {
        operations[index] = try decodeOperation(allocator, try object(value));
    }
    return .{
        .id = try duplicateString(allocator, try string(try required(item, "id"))),
        .parameters = parameters,
        .operations = operations,
    };
}

fn decodeOperation(allocator: std.mem.Allocator, item: std.json.ObjectMap) !Operation {
    const op = try string(try required(item, "op"));
    if (std.mem.eql(u8, op, "const")) {
        return .{ .const_integer = .{
            .id = try duplicateString(allocator, try string(try required(item, "id"))),
            .type = try decodeType(try required(item, "type")),
            .value = try integer(try required(item, "value")),
        } };
    }
    if (std.mem.eql(u8, op, "return")) {
        const value = try object(try required(item, "value"));
        const raw_index = try integer(try required(value, "result_index"));
        if (raw_index < 0 or raw_index > std.math.maxInt(u32)) return error.InvalidField;
        return .{ .return_value = .{
            .id = try duplicateString(allocator, try string(try required(item, "id"))),
            .value = .{
                .operation_id = try duplicateString(allocator, try string(try required(value, "operation_id"))),
                .result_index = @intCast(raw_index),
            },
        } };
    }
    return error.InvalidField;
}

/// Validates canonical graph semantics. Future CBOR or binary decoders call
/// this same function and therefore share precisely the same semantic rules.
pub fn validateGraph(graph: Graph, allocator: std.mem.Allocator) !void {
    var ids = std.StringHashMap(void).init(allocator);
    defer ids.deinit();
    var names = std.StringHashMap(void).init(allocator);
    defer names.deinit();

    for (graph.declarations) |declaration| {
        if (ids.contains(declaration.id())) return error.DuplicateDeclarationId;
        if (names.contains(declaration.name())) return error.DuplicateDeclarationName;
        try ids.put(declaration.id(), {});
        try names.put(declaration.name(), {});
        switch (declaration) {
            .function_decl => |function| try validateFunction(function, allocator),
            else => {},
        }
    }
}

fn validateFunction(function: FunctionDeclaration, allocator: std.mem.Allocator) !void {
    var block_ids = std.StringHashMap(void).init(allocator);
    defer block_ids.deinit();
    var operation_ids = std.StringHashMap(void).init(allocator);
    defer operation_ids.deinit();
    for (function.body.blocks) |block| {
        if (block_ids.contains(block.id)) return error.DuplicateBlockId;
        try block_ids.put(block.id, {});
        try validateBlock(block, function.result, &operation_ids, allocator);
    }
    if (!block_ids.contains(function.body.entry)) return error.MissingEntryBlock;
}

fn validateBlock(
    block: Block,
    function_result: ScalarType,
    operation_ids: *std.StringHashMap(void),
    allocator: std.mem.Allocator,
) !void {
    if (block.operations.len == 0) return error.MissingTerminator;

    var values = std.StringHashMap(ScalarType).init(allocator);
    defer values.deinit();

    for (block.operations, 0..) |operation, index| {
        if (operation_ids.contains(operation.id())) return error.DuplicateOperationId;
        try operation_ids.put(operation.id(), {});

        if (operation.isTerminator() and index + 1 != block.operations.len) return error.UnexpectedTerminator;
        if (!operation.isTerminator() and index + 1 == block.operations.len) return error.MissingTerminator;

        switch (operation) {
            .const_integer => |constant| {
                if (!integerFits(constant.value, constant.type)) return error.ConstantOutOfRange;
                try values.put(constant.id, constant.type);
            },
            .return_value => |return_value| {
                if (return_value.value.result_index != 0) return error.InvalidResultIndex;
                const value_type = values.get(return_value.value.operation_id) orelse return error.UnknownValue;
                if (value_type != function_result) return error.ReturnTypeMismatch;
            },
        }
    }
}

fn integerFits(value: i64, type_: ScalarType) bool {
    return switch (type_) {
        .i8 => value >= -128 and value <= 127,
        .i16 => value >= -32768 and value <= 32767,
        .i32 => value >= -2147483648 and value <= 2147483647,
        .i64 => true,
        .u8 => value >= 0 and value <= 255,
        .u16 => value >= 0 and value <= 65535,
        .u32 => value >= 0 and value <= 4294967295,
        .u64 => value >= 0,
        else => false,
    };
}

fn decodeTarget(value: []const u8) ValidationError!Target {
    if (std.mem.eql(u8, value, "aarch64-macos-none")) return .aarch64_macos;
    if (std.mem.eql(u8, value, "x86_64-macos-none")) return .x86_64_macos;
    if (std.mem.eql(u8, value, "x86_64-linux-gnu")) return .x86_64_linux;
    return error.UnsupportedTarget;
}

fn decodeType(value: std.json.Value) ValidationError!ScalarType {
    const name = try string(value);
    if (std.mem.eql(u8, name, "unit")) return .unit;
    if (std.mem.eql(u8, name, "bool")) return .boolean;
    if (std.mem.eql(u8, name, "i8")) return .i8;
    if (std.mem.eql(u8, name, "i16")) return .i16;
    if (std.mem.eql(u8, name, "i32")) return .i32;
    if (std.mem.eql(u8, name, "i64")) return .i64;
    if (std.mem.eql(u8, name, "u8")) return .u8;
    if (std.mem.eql(u8, name, "u16")) return .u16;
    if (std.mem.eql(u8, name, "u32")) return .u32;
    if (std.mem.eql(u8, name, "u64")) return .u64;
    if (std.mem.eql(u8, name, "f32")) return .f32;
    if (std.mem.eql(u8, name, "f64")) return .f64;
    return error.InvalidField;
}

fn decodeRepresentation(value: []const u8) ValidationError!Representation {
    if (std.mem.eql(u8, value, "native")) return .native;
    if (std.mem.eql(u8, value, "c")) return .c;
    return error.InvalidField;
}

fn decodeVisibility(value: []const u8) ValidationError!Visibility {
    if (std.mem.eql(u8, value, "private")) return .private;
    if (std.mem.eql(u8, value, "public")) return .public;
    return error.InvalidField;
}

fn duplicateString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return allocator.dupe(u8, value);
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

fn integer(value: std.json.Value) ValidationError!i64 {
    return switch (value) {
        .integer => |item| item,
        else => error.InvalidField,
    };
}

fn expectStringEqual(value: std.json.Value, expected: []const u8) ValidationError!void {
    if (!std.mem.eql(u8, try string(value), expected)) return error.InvalidField;
}

test "decodes and validates a typed constant and return" {
    const snapshot =
        \\{"protocol":"lil.wire/0","kind":"snapshot","optional_metadata":{},"body":{"id":"module.main","format_version":"lil.cpg/0","language_version":"0.1","target":"aarch64-macos-none","dependencies":[],"declarations":[{"kind":"function","id":"fn.main","name":"main","visibility":"public","parameters":[],"result":"i32","effects":[],"body":{"entry":"entry","blocks":[{"id":"entry","parameters":[],"operations":[{"op":"const","id":"op.answer","type":"i32","value":42},{"op":"return","id":"term.return","value":{"operation_id":"op.answer","result_index":0}}]}]}}]}}
    ;
    var decoded = try decodeJsonSnapshot(std.testing.allocator, snapshot);
    defer decoded.deinit();
    try std.testing.expectEqual(Target.aarch64_macos, decoded.graph.target);
    try std.testing.expectEqual(@as(usize, 1), decoded.graph.declarations.len);
    try validateGraph(decoded.graph, std.testing.allocator);
}

test "rejects an unsupported wire target" {
    const snapshot =
        \\{"protocol":"lil.wire/0","kind":"snapshot","optional_metadata":{},"body":{"id":"module.main","format_version":"lil.cpg/0","language_version":"0.1","target":"wasm32-freestanding","dependencies":[],"declarations":[]}}
    ;
    try std.testing.expectError(error.UnsupportedTarget, decodeJsonSnapshot(std.testing.allocator, snapshot));
}

test "graph validation rejects duplicate declaration names" {
    const declarations = [_]Declaration{
        .{ .struct_decl = .{ .id = "type.one", .name = "Thing", .repr = .native, .fields = &.{} } },
        .{ .struct_decl = .{ .id = "type.two", .name = "Thing", .repr = .native, .fields = &.{} } },
    };
    const graph = Graph{ .id = "module.main", .target = .aarch64_macos, .declarations = &declarations };
    try std.testing.expectError(error.DuplicateDeclarationName, validateGraph(graph, std.testing.allocator));
}

test "graph validation rejects a missing entry block" {
    const declarations = [_]Declaration{.{ .function_decl = .{
        .id = "fn.main",
        .name = "main",
        .visibility = .public,
        .parameters = &.{},
        .result = .i32,
        .effects = &.{},
        .body = .{ .entry = "entry", .blocks = &.{} },
    } }};
    const graph = Graph{ .id = "module.main", .target = .aarch64_macos, .declarations = &declarations };
    try std.testing.expectError(error.MissingEntryBlock, validateGraph(graph, std.testing.allocator));
}

test "graph validation rejects a return with the wrong type" {
    const operations = [_]Operation{
        .{ .const_integer = .{ .id = "op.value", .type = .i64, .value = 42 } },
        .{ .return_value = .{ .id = "term.return", .value = .{ .operation_id = "op.value", .result_index = 0 } } },
    };
    const blocks = [_]Block{.{ .id = "entry", .parameters = &.{}, .operations = &operations }};
    const declarations = [_]Declaration{.{ .function_decl = .{
        .id = "fn.main",
        .name = "main",
        .visibility = .public,
        .parameters = &.{},
        .result = .i32,
        .effects = &.{},
        .body = .{ .entry = "entry", .blocks = &blocks },
    } }};
    const graph = Graph{ .id = "module.main", .target = .aarch64_macos, .declarations = &declarations };
    try std.testing.expectError(error.ReturnTypeMismatch, validateGraph(graph, std.testing.allocator));
}

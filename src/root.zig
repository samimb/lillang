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
    BinaryOperandTypeMismatch,
    NonIntegerOperation,
    EntryFunctionMissing,
    InvalidEntryFunction,
};

/// The canonical program representation. It is independent of JSON, rendering
/// syntax, model handles, and storage format.
pub const Graph = struct {
    id: []const u8,
    target: Target,
    dependencies: []const Dependency,
    declarations: []const Declaration,
};

pub const Dependency = struct {
    module_name: []const u8,
    source_digest: []const u8,
    version: []const u8,
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

pub const WrappingAdd = struct {
    id: []const u8,
    type: ScalarType,
    left: ValueRef,
    right: ValueRef,
};

pub const Operation = union(enum) {
    const_integer: IntegerConstant,
    wrapping_add: WrappingAdd,
    return_value: Return,

    pub fn id(self: Operation) []const u8 {
        return switch (self) {
            .const_integer => |value| value.id,
            .wrapping_add => |value| value.id,
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
        .dependencies = try decodeDependencies(allocator, try array(try required(module, "dependencies"))),
        .declarations = declarations,
    };
}

fn decodeDependencies(allocator: std.mem.Allocator, dependencies_json: std.json.Array) ![]const Dependency {
    const dependencies = try allocator.alloc(Dependency, dependencies_json.items.len);
    for (dependencies_json.items, 0..) |value, index| {
        const dependency = try object(value);
        dependencies[index] = .{
            .module_name = try duplicateString(allocator, try string(try required(dependency, "module_name"))),
            .source_digest = try duplicateString(allocator, try string(try required(dependency, "source_digest"))),
            .version = try duplicateString(allocator, try string(try required(dependency, "version"))),
        };
    }
    return dependencies;
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
    if (std.mem.eql(u8, op, "add.wrapping")) {
        return .{ .wrapping_add = .{
            .id = try duplicateString(allocator, try string(try required(item, "id"))),
            .type = try decodeType(try required(item, "type")),
            .left = try decodeValueRef(allocator, try object(try required(item, "left"))),
            .right = try decodeValueRef(allocator, try object(try required(item, "right"))),
        } };
    }
    if (std.mem.eql(u8, op, "return")) {
        return .{ .return_value = .{
            .id = try duplicateString(allocator, try string(try required(item, "id"))),
            .value = try decodeValueRef(allocator, try object(try required(item, "value"))),
        } };
    }
    return error.InvalidField;
}

fn decodeValueRef(allocator: std.mem.Allocator, item: std.json.ObjectMap) !ValueRef {
    const raw_index = try integer(try required(item, "result_index"));
    if (raw_index < 0 or raw_index > std.math.maxInt(u32)) return error.InvalidField;
    return .{
        .operation_id = try duplicateString(allocator, try string(try required(item, "operation_id"))),
        .result_index = @intCast(raw_index),
    };
}

/// Encodes the implemented graph subset using the canonical `lil.wire/0`
/// JSON ordering. This is a wire adapter; `Graph` remains authoritative.
pub fn encodeJsonSnapshot(allocator: std.mem.Allocator, graph: Graph) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;

    try writer.writeAll("{\"body\":{");
    try writeKey(writer, "declarations");
    try writeDeclarations(writer, graph.declarations);
    try writer.writeAll(",");
    try writeKey(writer, "dependencies");
    try writeDependencies(writer, graph.dependencies);
    try writer.writeAll(",");
    try writeKeyString(writer, "format_version", format_version);
    try writer.writeAll(",");
    try writeKeyString(writer, "id", graph.id);
    try writer.writeAll(",");
    try writeKeyString(writer, "language_version", language_version);
    try writer.writeAll(",");
    try writeKeyString(writer, "target", graph.target.wireName());
    try writer.writeAll("},\"kind\":\"snapshot\",\"optional_metadata\":{},\"protocol\":\"lil.wire/0\"}");
    return output.toOwnedSlice();
}

/// SHA-256 of canonical wire bytes, encoded as 64 lowercase hexadecimal bytes.
pub fn snapshotDigest(bytes: []const u8) [64]u8 {
    var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    const alphabet = "0123456789abcdef";
    var result: [64]u8 = undefined;
    for (hash, 0..) |byte, index| {
        result[index * 2] = alphabet[byte >> 4];
        result[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return result;
}

fn writeKey(writer: *std.Io.Writer, key: []const u8) !void {
    try std.json.Stringify.value(key, .{}, writer);
    try writer.writeAll(":");
}

fn writeString(writer: *std.Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn writeKeyString(writer: *std.Io.Writer, key: []const u8, value: []const u8) !void {
    try writeKey(writer, key);
    try writeString(writer, value);
}

fn writeDependencies(writer: *std.Io.Writer, dependencies: []const Dependency) !void {
    try writer.writeAll("[");
    for (dependencies, 0..) |dependency, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.writeAll("{");
        try writeKeyString(writer, "module_name", dependency.module_name);
        try writer.writeAll(",");
        try writeKeyString(writer, "source_digest", dependency.source_digest);
        try writer.writeAll(",");
        try writeKeyString(writer, "version", dependency.version);
        try writer.writeAll("}");
    }
    try writer.writeAll("]");
}

fn writeDeclarations(writer: *std.Io.Writer, declarations: []const Declaration) !void {
    try writer.writeAll("[");
    for (declarations, 0..) |declaration, index| {
        if (index != 0) try writer.writeAll(",");
        switch (declaration) {
            .struct_decl => |value| try writeStructDeclaration(writer, value),
            .function_decl => |value| try writeFunctionDeclaration(writer, value),
            .external_function_decl => |value| try writeExternalFunctionDeclaration(writer, value),
        }
    }
    try writer.writeAll("]");
}

fn writeStructDeclaration(writer: *std.Io.Writer, declaration: StructDeclaration) !void {
    try writer.writeAll("{");
    try writeKey(writer, "fields");
    try writer.writeAll("[");
    for (declaration.fields, 0..) |field, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.writeAll("{");
        try writeKeyString(writer, "name", field.name);
        try writer.writeAll(",");
        try writeKeyString(writer, "type", typeName(field.type));
        try writer.writeAll("}");
    }
    try writer.writeAll("],");
    try writeKeyString(writer, "id", declaration.id);
    try writer.writeAll(",\"kind\":\"struct\",");
    try writeKeyString(writer, "name", declaration.name);
    try writer.writeAll(",");
    try writeKeyString(writer, "repr", representationName(declaration.repr));
    try writer.writeAll("}");
}

fn writeFunctionDeclaration(writer: *std.Io.Writer, declaration: FunctionDeclaration) !void {
    try writer.writeAll("{");
    try writeKey(writer, "body");
    try writeFunctionBody(writer, declaration.body);
    try writer.writeAll(",\"effects\":[");
    for (declaration.effects, 0..) |_, index| {
        if (index != 0) try writer.writeAll(",");
        try writeString(writer, "UnsafeFFI");
    }
    try writer.writeAll("],");
    try writeKeyString(writer, "id", declaration.id);
    try writer.writeAll(",\"kind\":\"function\",");
    try writeKeyString(writer, "name", declaration.name);
    try writer.writeAll(",");
    try writeParameters(writer, declaration.parameters);
    try writer.writeAll(",");
    try writeKeyString(writer, "result", typeName(declaration.result));
    try writer.writeAll(",");
    try writeKeyString(writer, "visibility", visibilityName(declaration.visibility));
    try writer.writeAll("}");
}

fn writeExternalFunctionDeclaration(writer: *std.Io.Writer, declaration: ExternalFunctionDeclaration) !void {
    try writer.writeAll("{");
    try writeKeyString(writer, "c_symbol", declaration.c_symbol);
    try writer.writeAll(",");
    try writeKeyString(writer, "calling_convention", declaration.calling_convention);
    try writer.writeAll(",");
    try writeKeyString(writer, "id", declaration.id);
    try writer.writeAll(",\"kind\":\"external_function\",");
    try writeKeyString(writer, "library", declaration.library);
    try writer.writeAll(",");
    try writeKeyString(writer, "name", declaration.name);
    try writer.writeAll(",\"parameters\":[");
    for (declaration.parameters, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(",");
        try writeString(writer, typeName(parameter));
    }
    try writer.writeAll("],");
    try writeKeyString(writer, "result", typeName(declaration.result));
    try writer.writeAll("}");
}

fn writeParameters(writer: *std.Io.Writer, parameters: []const Parameter) !void {
    try writeKey(writer, "parameters");
    try writer.writeAll("[");
    for (parameters, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.writeAll("{");
        try writeKeyString(writer, "name", parameter.name);
        try writer.writeAll(",");
        try writeKeyString(writer, "type", typeName(parameter.type));
        try writer.writeAll("}");
    }
    try writer.writeAll("]");
}

fn writeFunctionBody(writer: *std.Io.Writer, body: FunctionBody) !void {
    try writer.writeAll("{");
    try writeKey(writer, "blocks");
    try writer.writeAll("[");
    for (body.blocks, 0..) |block, index| {
        if (index != 0) try writer.writeAll(",");
        try writeBlock(writer, block);
    }
    try writer.writeAll("],");
    try writeKeyString(writer, "entry", body.entry);
    try writer.writeAll("}");
}

fn writeBlock(writer: *std.Io.Writer, block: Block) !void {
    try writer.writeAll("{");
    try writeKeyString(writer, "id", block.id);
    try writer.writeAll(",\"operations\":[");
    for (block.operations, 0..) |operation, index| {
        if (index != 0) try writer.writeAll(",");
        try writeOperation(writer, operation);
    }
    try writer.writeAll("],\"parameters\":[");
    for (block.parameters, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.writeAll("{");
        try writeKeyString(writer, "id", parameter.id);
        try writer.writeAll(",");
        try writeKeyString(writer, "type", typeName(parameter.type));
        try writer.writeAll("}");
    }
    try writer.writeAll("]}");
}

fn writeOperation(writer: *std.Io.Writer, operation: Operation) !void {
    switch (operation) {
        .const_integer => |value| {
            try writer.writeAll("{");
            try writeKeyString(writer, "id", value.id);
            try writer.writeAll(",\"op\":\"const\",");
            try writeKeyString(writer, "type", typeName(value.type));
            try writer.print(",\"value\":{d}", .{value.value});
            try writer.writeAll("}");
        },
        .wrapping_add => |value| {
            try writer.writeAll("{");
            try writeKeyString(writer, "id", value.id);
            try writer.writeAll(",\"left\":");
            try writeValueRef(writer, value.left);
            try writer.writeAll(",\"op\":\"add.wrapping\",\"right\":");
            try writeValueRef(writer, value.right);
            try writer.writeAll(",");
            try writeKeyString(writer, "type", typeName(value.type));
            try writer.writeAll("}");
        },
        .return_value => |value| {
            try writer.writeAll("{");
            try writeKeyString(writer, "id", value.id);
            try writer.writeAll(",\"op\":\"return\",\"value\":");
            try writeValueRef(writer, value.value);
            try writer.writeAll("}");
        },
    }
}

fn writeValueRef(writer: *std.Io.Writer, value: ValueRef) !void {
    try writer.writeAll("{");
    try writeKeyString(writer, "operation_id", value.operation_id);
    try writer.print(",\"result_index\":{d}", .{value.result_index});
    try writer.writeAll("}");
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
            .wrapping_add => |add| {
                if (!isInteger(add.type)) return error.NonIntegerOperation;
                const left_type = try resolveLocalValue(&values, add.left);
                const right_type = try resolveLocalValue(&values, add.right);
                if (left_type != add.type or right_type != add.type) return error.BinaryOperandTypeMismatch;
                try values.put(add.id, add.type);
            },
            .return_value => |return_value| {
                const value_type = try resolveLocalValue(&values, return_value.value);
                if (value_type != function_result) return error.ReturnTypeMismatch;
            },
        }
    }
}

fn resolveLocalValue(values: *const std.StringHashMap(ScalarType), reference: ValueRef) ValidationError!ScalarType {
    if (reference.result_index != 0) return error.InvalidResultIndex;
    return values.get(reference.operation_id) orelse error.UnknownValue;
}

fn isInteger(type_: ScalarType) bool {
    return switch (type_) {
        .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => true,
        else => false,
    };
}

/// Produces the stable human and model projection for the implemented graph
/// subset. This is inspection text, not a second source representation.
pub fn renderGraph(allocator: std.mem.Allocator, graph: Graph) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;

    try writer.print("module {s} target {s}\n", .{ graph.id, graph.target.wireName() });
    for (graph.declarations) |declaration| {
        switch (declaration) {
            .struct_decl => |struct_decl| try renderStruct(writer, struct_decl),
            .function_decl => |function| try renderFunction(writer, function),
            .external_function_decl => |external_function| try writer.print(
                "extern fn {s} -> {s} @c({s}, {s})\n",
                .{ external_function.name, typeName(external_function.result), external_function.c_symbol, external_function.library },
            ),
        }
    }
    return output.toOwnedSlice();
}

pub const IntegerValue = union(enum) {
    signed: i64,
    unsigned: u64,

    pub fn format(self: IntegerValue, writer: *std.Io.Writer) !void {
        switch (self) {
            .signed => |value| try writer.print("{d}", .{value}),
            .unsigned => |value| try writer.print("{d}", .{value}),
        }
    }
};

/// Interprets the current straight-line Core IR subset. It is a semantic
/// reference implementation, not the eventual native compiler backend.
pub fn evaluateMain(graph: Graph, allocator: std.mem.Allocator) !IntegerValue {
    try validateGraph(graph, allocator);

    var entry: ?FunctionDeclaration = null;
    for (graph.declarations) |declaration| switch (declaration) {
        .function_decl => |function| {
            if (function.visibility == .public and std.mem.eql(u8, function.name, "main")) {
                if (entry != null) return error.InvalidEntryFunction;
                entry = function;
            }
        },
        else => {},
    };
    const function = entry orelse return error.EntryFunctionMissing;
    if (function.parameters.len != 0 or function.effects.len != 0 or !isInteger(function.result)) return error.InvalidEntryFunction;

    var block: ?Block = null;
    for (function.body.blocks) |candidate| {
        if (std.mem.eql(u8, candidate.id, function.body.entry)) block = candidate;
    }
    const entry_block = block orelse return error.InvalidEntryFunction;

    var values = std.StringHashMap(IntegerValue).init(allocator);
    defer values.deinit();
    for (entry_block.operations) |operation| switch (operation) {
        .const_integer => |constant| try values.put(constant.id, integerConstantValue(constant)),
        .wrapping_add => |add| {
            const left = values.get(add.left.operation_id) orelse return error.UnknownValue;
            const right = values.get(add.right.operation_id) orelse return error.UnknownValue;
            try values.put(add.id, wrappingAdd(add.type, left, right));
        },
        .return_value => |return_value| return values.get(return_value.value.operation_id) orelse error.UnknownValue,
    };
    return error.InvalidEntryFunction;
}

fn integerConstantValue(constant: IntegerConstant) IntegerValue {
    return switch (constant.type) {
        .u8, .u16, .u32, .u64 => .{ .unsigned = @intCast(constant.value) },
        else => .{ .signed = constant.value },
    };
}

fn wrappingAdd(type_: ScalarType, left: IntegerValue, right: IntegerValue) IntegerValue {
    return switch (type_) {
        .i8 => .{ .signed = @as(i8, @intCast(left.signed)) +% @as(i8, @intCast(right.signed)) },
        .i16 => .{ .signed = @as(i16, @intCast(left.signed)) +% @as(i16, @intCast(right.signed)) },
        .i32 => .{ .signed = @as(i32, @intCast(left.signed)) +% @as(i32, @intCast(right.signed)) },
        .i64 => .{ .signed = left.signed +% right.signed },
        .u8 => .{ .unsigned = @as(u8, @intCast(left.unsigned)) +% @as(u8, @intCast(right.unsigned)) },
        .u16 => .{ .unsigned = @as(u16, @intCast(left.unsigned)) +% @as(u16, @intCast(right.unsigned)) },
        .u32 => .{ .unsigned = @as(u32, @intCast(left.unsigned)) +% @as(u32, @intCast(right.unsigned)) },
        .u64 => .{ .unsigned = left.unsigned +% right.unsigned },
        else => unreachable,
    };
}

fn renderStruct(writer: *std.Io.Writer, struct_decl: StructDeclaration) !void {
    try writer.print("struct {s} repr({s}) {{\n", .{ struct_decl.name, representationName(struct_decl.repr) });
    for (struct_decl.fields) |field| try writer.print("  {s}: {s}\n", .{ field.name, typeName(field.type) });
    try writer.writeAll("}\n");
}

fn renderFunction(writer: *std.Io.Writer, function: FunctionDeclaration) !void {
    if (function.visibility == .public) try writer.writeAll("pub ");
    try writer.print("fn {s}(", .{function.name});
    for (function.parameters, 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s}: {s}", .{ parameter.name, typeName(parameter.type) });
    }
    try writer.print(") -> {s}", .{typeName(function.result)});
    if (function.effects.len != 0) try writer.writeAll(" ![UnsafeFFI]");
    try writer.writeAll(" {\n");
    for (function.body.blocks) |block| {
        try writer.print("  block {s}:\n", .{block.id});
        for (block.operations) |operation| try renderOperation(writer, operation);
    }
    try writer.writeAll("}\n");
}

fn renderOperation(writer: *std.Io.Writer, operation: Operation) !void {
    switch (operation) {
        .const_integer => |constant| try writer.print(
            "    %{s}: {s} = const {d}\n",
            .{ constant.id, typeName(constant.type), constant.value },
        ),
        .wrapping_add => |add| try writer.print(
            "    %{s}: {s} = add.wrapping %{s}[{d}], %{s}[{d}]\n",
            .{ add.id, typeName(add.type), add.left.operation_id, add.left.result_index, add.right.operation_id, add.right.result_index },
        ),
        .return_value => |return_value| try writer.print(
            "    return %{s}[{d}]\n",
            .{ return_value.value.operation_id, return_value.value.result_index },
        ),
    }
}

fn typeName(type_: ScalarType) []const u8 {
    return switch (type_) {
        .unit => "unit", .boolean => "bool", .i8 => "i8", .i16 => "i16", .i32 => "i32", .i64 => "i64",
        .u8 => "u8", .u16 => "u16", .u32 => "u32", .u64 => "u64", .f32 => "f32", .f64 => "f64",
    };
}

fn representationName(repr: Representation) []const u8 {
    return switch (repr) { .native => "native", .c => "c" };
}

fn visibilityName(visibility: Visibility) []const u8 {
    return switch (visibility) { .private => "private", .public => "public" };
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
    const graph = Graph{ .id = "module.main", .target = .aarch64_macos, .dependencies = &.{}, .declarations = &declarations };
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
    const graph = Graph{ .id = "module.main", .target = .aarch64_macos, .dependencies = &.{}, .declarations = &declarations };
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
    const graph = Graph{ .id = "module.main", .target = .aarch64_macos, .dependencies = &.{}, .declarations = &declarations };
    try std.testing.expectError(error.ReturnTypeMismatch, validateGraph(graph, std.testing.allocator));
}

test "renders the canonical graph deterministically" {
    const operations = [_]Operation{
        .{ .const_integer = .{ .id = "op.answer", .type = .i32, .value = 42 } },
        .{ .return_value = .{ .id = "term.return", .value = .{ .operation_id = "op.answer", .result_index = 0 } } },
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
    const graph = Graph{ .id = "module.main", .target = .aarch64_macos, .dependencies = &.{}, .declarations = &declarations };
    const rendered = try renderGraph(std.testing.allocator, graph);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        \\module module.main target aarch64-macos-none
        \\pub fn main() -> i32 {
        \\  block entry:
        \\    %op.answer: i32 = const 42
        \\    return %op.answer[0]
        \\}
        \\
    ,
        rendered,
    );
}

test "interpreter applies i8 wrapping addition" {
    const operations = [_]Operation{
        .{ .const_integer = .{ .id = "op.max", .type = .i8, .value = 127 } },
        .{ .const_integer = .{ .id = "op.one", .type = .i8, .value = 1 } },
        .{ .wrapping_add = .{
            .id = "op.wrapped",
            .type = .i8,
            .left = .{ .operation_id = "op.max", .result_index = 0 },
            .right = .{ .operation_id = "op.one", .result_index = 0 },
        } },
        .{ .return_value = .{ .id = "term.return", .value = .{ .operation_id = "op.wrapped", .result_index = 0 } } },
    };
    const blocks = [_]Block{.{ .id = "entry", .parameters = &.{}, .operations = &operations }};
    const declarations = [_]Declaration{.{ .function_decl = .{
        .id = "fn.main",
        .name = "main",
        .visibility = .public,
        .parameters = &.{},
        .result = .i8,
        .effects = &.{},
        .body = .{ .entry = "entry", .blocks = &blocks },
    } }};
    const graph = Graph{ .id = "module.main", .target = .aarch64_macos, .dependencies = &.{}, .declarations = &declarations };
    const result = try evaluateMain(graph, std.testing.allocator);
    try std.testing.expectEqual(IntegerValue{ .signed = -128 }, result);
}

test "canonical JSON round trips and has a stable digest" {
    const snapshot =
        \\{"protocol":"lil.wire/0","kind":"snapshot","optional_metadata":{},"body":{"target":"aarch64-macos-none","id":"module.main","language_version":"0.1","format_version":"lil.cpg/0","dependencies":[{"version":"1.2.3","module_name":"math","source_digest":"abcd"}],"declarations":[{"kind":"function","id":"fn.main","name":"main","visibility":"public","parameters":[],"result":"i32","effects":[],"body":{"entry":"entry","blocks":[{"id":"entry","parameters":[],"operations":[{"op":"const","id":"op.answer","type":"i32","value":42},{"op":"return","id":"term.return","value":{"operation_id":"op.answer","result_index":0}}]}]}}]}}
    ;
    var first_graph = try decodeJsonSnapshot(std.testing.allocator, snapshot);
    defer first_graph.deinit();
    try std.testing.expectEqual(@as(usize, 1), first_graph.graph.dependencies.len);

    const first = try encodeJsonSnapshot(std.testing.allocator, first_graph.graph);
    defer std.testing.allocator.free(first);
    var second_graph = try decodeJsonSnapshot(std.testing.allocator, first);
    defer second_graph.deinit();
    const second = try encodeJsonSnapshot(std.testing.allocator, second_graph.graph);
    defer std.testing.allocator.free(second);

    try std.testing.expectEqualStrings(first, second);
    try std.testing.expectEqual(snapshotDigest(first), snapshotDigest(second));
}

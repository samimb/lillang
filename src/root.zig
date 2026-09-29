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

pub const Diagnostic = struct {
    code: ValidationError,
    object_id: []const u8,
    rule: []const u8,
};

pub const TransactionError = error{
    StaleBase,
    UnknownDeclaration,
    InvalidResultingGraph,
};

pub const RenameDeclaration = struct {
    id: []const u8,
    new_name: []const u8,
};

/// The first implemented transaction operation. The fixed base digest prevents
/// accidentally applying an otherwise-valid edit to a different graph state.
pub const Transaction = struct {
    base_digest: [64]u8,
    renames: []const RenameDeclaration,
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
    arena: *std.heap.ArenaAllocator,
    graph: Graph,

    pub fn deinit(self: *DecodedSnapshot) void {
        const backing_allocator = self.arena.child_allocator;
        self.arena.deinit();
        backing_allocator.destroy(self.arena);
    }
};

/// A decoded model program keeps the graph with the ABI identity that gave its
/// raw token IDs meaning. Persistence can store this pair without retaining a
/// human rendering or tokenizer-dependent textual spelling.
pub const DecodedTokenProgram = struct {
    arena: *std.heap.ArenaAllocator,
    graph: Graph,
    abi_version: []const u8,
    token_count: usize,

    pub fn deinit(self: *DecodedTokenProgram) void {
        const backing_allocator = self.arena.child_allocator;
        self.arena.deinit();
        backing_allocator.destroy(self.arena);
    }
};

/// The model-facing ABI is a stream of these raw IDs.  The names below are
/// implementation documentation only; the IDs, not their spellings, are what
/// an ABI-compatible model emits.
pub const token_abi_version = "lil.token/0";
pub const TokenId = u16;

pub const TokenAbi = struct {
    pub const module_begin: TokenId = 0x0001;
    pub const module_end: TokenId = 0x0002;
    pub const function_main_i32: TokenId = 0x0010;
    pub const function_end: TokenId = 0x0011;
    pub const const_i32: TokenId = 0x0020;
    pub const add_wrapping_i32: TokenId = 0x0021;
    pub const return_i32: TokenId = 0x0022;

    // Dense ABI ranges avoid a textual literal grammar.  This v0 slice uses
    // signed 12-bit immediates and local value handles 0 through 4095.
    pub const literal_i32_base: TokenId = 0x1000;
    pub const literal_i32_count: TokenId = 0x1000;
    pub const value_ref_base: TokenId = 0x3000;
    pub const value_ref_count: TokenId = 0x1000;

    pub fn literalI32(value: i32) error{LiteralOutOfRange}!TokenId {
        if (value < -2048 or value > 2047) return error.LiteralOutOfRange;
        return literal_i32_base + @as(TokenId, @intCast(value + 2048));
    }

    pub fn valueRef(index: u16) error{ValueReferenceOutOfRange}!TokenId {
        if (index >= value_ref_count) return error.ValueReferenceOutOfRange;
        return value_ref_base + index;
    }

    pub fn decodeLiteralI32(id: TokenId) ?i32 {
        if (id < literal_i32_base or id >= literal_i32_base + literal_i32_count) return null;
        return @as(i32, id - literal_i32_base) - 2048;
    }

    pub fn decodeValueRef(id: TokenId) ?u16 {
        if (id < value_ref_base or id >= value_ref_base + value_ref_count) return null;
        return id - value_ref_base;
    }
};

pub const DecoderError = error{
    UnexpectedToken,
    InvalidLiteralToken,
    InvalidValueReference,
    ValueTypeMismatch,
    ValueTableFull,
    IncompleteProgram,
    ProgramAlreadyFinished,
};

pub const DecoderState = enum {
    expect_module_begin,
    expect_function_or_module_end,
    expect_operation,
    expect_i32_literal,
    expect_add_left,
    expect_add_right,
    expect_return_value,
    expect_function_end,
    complete,
};

/// A compact description of the vocabulary legal at a decoder boundary. A
/// serving runtime can turn this into a token mask without asking the model to
/// reason about syntax, arity, scope, or integer types.
pub const NextTokenConstraint = union(enum) {
    exact: []const TokenId,
    i32_literal,
    i32_value_ref: u16,
    terminal,
};

const module_start_tokens = [_]TokenId{TokenAbi.module_begin};
const function_start_tokens = [_]TokenId{TokenAbi.function_main_i32};
const module_end_tokens = [_]TokenId{TokenAbi.module_end};
const operation_tokens = [_]TokenId{ TokenAbi.const_i32, TokenAbi.add_wrapping_i32, TokenAbi.return_i32 };
const function_end_tokens = [_]TokenId{TokenAbi.function_end};

/// Direct decoder from a semantic token stream to a typed graph. It deliberately
/// has no lexer or parser: every input is one ABI token and every state exposes
/// its legal continuation before the next token is accepted.
pub const SemanticDecoder = struct {
    backing_allocator: std.mem.Allocator,
    arena: ?*std.heap.ArenaAllocator,
    target: Target,
    state: DecoderState = .expect_module_begin,
    operations: []Operation,
    value_types: []ScalarType,
    operation_count: usize = 0,
    value_count: usize = 0,
    function_started: bool = false,
    function_finished: bool = false,
    pending_left: ?ValueRef = null,

    pub fn init(backing_allocator: std.mem.Allocator, target: Target, maximum_tokens: usize) !SemanticDecoder {
        const arena = try backing_allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(backing_allocator);
        errdefer {
            arena.deinit();
            backing_allocator.destroy(arena);
        }
        const arena_allocator = arena.allocator();
        return .{
            .backing_allocator = backing_allocator,
            .arena = arena,
            .target = target,
            .operations = try arena_allocator.alloc(Operation, maximum_tokens),
            .value_types = try arena_allocator.alloc(ScalarType, maximum_tokens),
        };
    }

    pub fn deinit(self: *SemanticDecoder) void {
        if (self.arena) |arena| {
            arena.deinit();
            self.backing_allocator.destroy(arena);
            self.arena = null;
        }
    }

    pub fn nextConstraint(self: *const SemanticDecoder) NextTokenConstraint {
        return switch (self.state) {
            .expect_module_begin => .{ .exact = &module_start_tokens },
            .expect_function_or_module_end => .{ .exact = if (self.function_finished) &module_end_tokens else &function_start_tokens },
            .expect_operation => .{ .exact = &operation_tokens },
            .expect_i32_literal => .i32_literal,
            .expect_add_left, .expect_add_right, .expect_return_value => .{ .i32_value_ref = @intCast(self.value_count) },
            .expect_function_end => .{ .exact = &function_end_tokens },
            .complete => .terminal,
        };
    }

    pub fn push(self: *SemanticDecoder, id: TokenId) !void {
        switch (self.state) {
            .expect_module_begin => {
                if (id != TokenAbi.module_begin) return error.UnexpectedToken;
                self.state = .expect_function_or_module_end;
            },
            .expect_function_or_module_end => {
                if (id == TokenAbi.function_main_i32 and !self.function_started) {
                    self.function_started = true;
                    self.state = .expect_operation;
                } else if (id == TokenAbi.module_end and self.function_finished) {
                    self.state = .complete;
                } else {
                    return error.UnexpectedToken;
                }
            },
            .expect_operation => switch (id) {
                TokenAbi.const_i32 => self.state = .expect_i32_literal,
                TokenAbi.add_wrapping_i32 => self.state = .expect_add_left,
                TokenAbi.return_i32 => self.state = .expect_return_value,
                else => return error.UnexpectedToken,
            },
            .expect_i32_literal => {
                const value = TokenAbi.decodeLiteralI32(id) orelse return error.InvalidLiteralToken;
                try self.appendConst(value);
                self.state = .expect_operation;
            },
            .expect_add_left => {
                self.pending_left = try self.i32ValueRef(id);
                self.state = .expect_add_right;
            },
            .expect_add_right => {
                const right = try self.i32ValueRef(id);
                try self.appendWrappingAdd(self.pending_left.?, right);
                self.pending_left = null;
                self.state = .expect_operation;
            },
            .expect_return_value => {
                const value = try self.i32ValueRef(id);
                try self.appendReturn(value);
                self.state = .expect_function_end;
            },
            .expect_function_end => {
                if (id != TokenAbi.function_end) return error.UnexpectedToken;
                self.function_finished = true;
                self.state = .expect_function_or_module_end;
            },
            .complete => return error.ProgramAlreadyFinished,
        }
    }

    pub fn finish(self: *SemanticDecoder) !DecodedSnapshot {
        if (self.state != .complete) return error.IncompleteProgram;
        const arena = self.arena orelse return error.ProgramAlreadyFinished;
        const arena_allocator = arena.allocator();
        const blocks = try arena_allocator.alloc(Block, 1);
        blocks[0] = .{
            .id = "latent.entry",
            .parameters = &.{},
            .operations = self.operations[0..self.operation_count],
        };
        const declarations = try arena_allocator.alloc(Declaration, 1);
        declarations[0] = .{ .function_decl = .{
            .id = "latent.fn.main",
            .name = "main",
            .visibility = .public,
            .parameters = &.{},
            .result = .i32,
            .effects = &.{},
            .body = .{ .entry = "latent.entry", .blocks = blocks },
        } };
        const graph = Graph{
            .id = "latent.module",
            .target = self.target,
            .dependencies = &.{},
            .declarations = declarations,
        };
        try validateGraph(graph, arena_allocator);
        self.arena = null;
        return .{ .arena = arena, .graph = graph };
    }

    fn allocator(self: *SemanticDecoder) std.mem.Allocator {
        return self.arena.?.allocator();
    }

    fn appendConst(self: *SemanticDecoder, value: i32) !void {
        if (self.value_count >= TokenAbi.value_ref_count) return error.ValueTableFull;
        const id = try std.fmt.allocPrint(self.allocator(), "latent.value.{d}", .{self.value_count});
        self.operations[self.operation_count] = .{ .const_integer = .{ .id = id, .type = .i32, .value = value } };
        self.operation_count += 1;
        self.value_types[self.value_count] = .i32;
        self.value_count += 1;
    }

    fn appendWrappingAdd(self: *SemanticDecoder, left: ValueRef, right: ValueRef) !void {
        if (self.value_count >= TokenAbi.value_ref_count) return error.ValueTableFull;
        const id = try std.fmt.allocPrint(self.allocator(), "latent.value.{d}", .{self.value_count});
        self.operations[self.operation_count] = .{ .wrapping_add = .{ .id = id, .type = .i32, .left = left, .right = right } };
        self.operation_count += 1;
        self.value_types[self.value_count] = .i32;
        self.value_count += 1;
    }

    fn appendReturn(self: *SemanticDecoder, value: ValueRef) !void {
        self.operations[self.operation_count] = .{ .return_value = .{ .id = "latent.return", .value = value } };
        self.operation_count += 1;
    }

    fn i32ValueRef(self: *const SemanticDecoder, id: TokenId) !ValueRef {
        const index = TokenAbi.decodeValueRef(id) orelse return error.InvalidValueReference;
        if (index >= self.value_count) return error.InvalidValueReference;
        if (self.value_types[index] != .i32) return error.ValueTypeMismatch;
        return .{ .operation_id = self.operations[index].id(), .result_index = 0 };
    }
};

/// Convenience entry point for clients that already have a complete model
/// output. Incremental clients should retain `SemanticDecoder` and query its
/// `nextConstraint` between token emissions.
pub fn decodeTokenIds(backing_allocator: std.mem.Allocator, target: Target, token_ids: []const TokenId) !DecodedTokenProgram {
    var decoder = try SemanticDecoder.init(backing_allocator, target, token_ids.len);
    defer decoder.deinit();
    for (token_ids) |id| try decoder.push(id);
    const snapshot = try decoder.finish();
    return .{
        .arena = snapshot.arena,
        .graph = snapshot.graph,
        .abi_version = token_abi_version,
        .token_count = token_ids.len,
    };
}

/// Structured feedback for a rejected model emission. The constraint is the
/// one that was in force before `received` was considered, so a caller can
/// immediately mask its vocabulary and retry without reconstructing state.
pub const DecoderDiagnostic = struct {
    token_offset: usize,
    received: ?TokenId,
    state: DecoderState,
    expected: NextTokenConstraint,
    target: Target,
    failure: anyerror,
};

pub fn diagnoseTokenIds(
    backing_allocator: std.mem.Allocator,
    target: Target,
    token_ids: []const TokenId,
) !?DecoderDiagnostic {
    var decoder = try SemanticDecoder.init(backing_allocator, target, token_ids.len);
    defer decoder.deinit();
    for (token_ids, 0..) |id, index| {
        const expected = decoder.nextConstraint();
        decoder.push(id) catch |err| {
            return .{
                .token_offset = index,
                .received = id,
                .state = decoder.state,
                .expected = expected,
                .target = target,
                .failure = err,
            };
        };
    }
    const expected = decoder.nextConstraint();
    var decoded = decoder.finish() catch |err| {
        return .{
            .token_offset = token_ids.len,
            .received = null,
            .state = decoder.state,
            .expected = expected,
            .target = target,
            .failure = err,
        };
    };
    decoded.deinit();
    return null;
}

/// Compact, projection-local symbol handles are never committed. The compiler
/// service resolves one to this stable declaration ID before it builds a graph
/// edit or records an audit event.
pub const ModelHandle = u16;

pub const ProjectionError = error{
    UnknownProjectionSymbol,
    DuplicateProjectionSymbol,
    ProjectionTooLarge,
    UnknownModelHandle,
};

pub const ProjectionAccounting = struct {
    projection_tokens: u64,
    retrieval_tokens: u64,
};

pub const ProjectionLedger = struct {
    entries: std.ArrayList(ProjectionAccounting) = .empty,

    pub fn deinit(self: *ProjectionLedger, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);
    }

    pub fn record(self: *ProjectionLedger, allocator: std.mem.Allocator, accounting: ProjectionAccounting) !void {
        try self.entries.append(allocator, accounting);
    }

    pub fn totals(self: *const ProjectionLedger) ProjectionAccounting {
        var result = ProjectionAccounting{ .projection_tokens = 0, .retrieval_tokens = 0 };
        for (self.entries.items) |entry| {
            result.projection_tokens += entry.projection_tokens;
            result.retrieval_tokens += entry.retrieval_tokens;
        }
        return result;
    }
};

pub const ProjectedSymbolKind = enum { function, structure, external_function };

pub const ProjectedSignature = union(ProjectedSymbolKind) {
    function: struct {
        parameters: []const ScalarType,
        result: ScalarType,
        effects: []const Effect,
    },
    structure: struct { fields: []const ScalarType },
    external_function: struct {
        parameters: []const ScalarType,
        result: ScalarType,
    },
};

pub const ProjectedSymbol = struct {
    handle: ModelHandle,
    stable_id: []const u8,
    display_name: []const u8,
    signature: ProjectedSignature,
};

/// A task-bounded, read-only view of only the declarations the caller asked
/// the compiler service to inject. It contains types and effects but no graph
/// mutation path and no text that can be interpreted as source.
pub const ScopedProjection = struct {
    arena: *std.heap.ArenaAllocator,
    graph_id: []const u8,
    symbols: []const ProjectedSymbol,
    accounting: ProjectionAccounting,

    pub fn deinit(self: *ScopedProjection) void {
        const backing_allocator = self.arena.child_allocator;
        self.arena.deinit();
        backing_allocator.destroy(self.arena);
    }

    pub fn resolveHandle(self: *const ScopedProjection, handle: ModelHandle) ProjectionError![]const u8 {
        for (self.symbols) |symbol| {
            if (symbol.handle == handle) return symbol.stable_id;
        }
        return error.UnknownModelHandle;
    }
};

/// Opens one immutable model projection. `requested_ids` are stable graph
/// identities, never names; requesting a declaration twice is rejected instead
/// of allocating aliases that could make a later edit ambiguous.
pub fn openScopedProjection(
    backing_allocator: std.mem.Allocator,
    ledger: *ProjectionLedger,
    graph: Graph,
    requested_ids: []const []const u8,
    accounting: ProjectionAccounting,
) !ScopedProjection {
    if (requested_ids.len > std.math.maxInt(ModelHandle)) return error.ProjectionTooLarge;
    const arena = try backing_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer {
        arena.deinit();
        backing_allocator.destroy(arena);
    }
    const allocator = arena.allocator();
    const symbols = try allocator.alloc(ProjectedSymbol, requested_ids.len);
    for (requested_ids, 0..) |requested_id, index| {
        for (requested_ids[0..index]) |earlier_id| {
            if (std.mem.eql(u8, requested_id, earlier_id)) return error.DuplicateProjectionSymbol;
        }
        const declaration = findDeclaration(graph, requested_id) orelse return error.UnknownProjectionSymbol;
        symbols[index] = try projectDeclaration(allocator, declaration, @intCast(index + 1));
    }
    try ledger.record(backing_allocator, accounting);
    return .{
        .arena = arena,
        .graph_id = try allocator.dupe(u8, graph.id),
        .symbols = symbols,
        .accounting = accounting,
    };
}

fn findDeclaration(graph: Graph, stable_id: []const u8) ?Declaration {
    for (graph.declarations) |declaration| {
        if (std.mem.eql(u8, declaration.id(), stable_id)) return declaration;
    }
    return null;
}

fn projectDeclaration(allocator: std.mem.Allocator, declaration: Declaration, handle: ModelHandle) !ProjectedSymbol {
    const stable_id = try allocator.dupe(u8, declaration.id());
    const display_name = try allocator.dupe(u8, declaration.name());
    return switch (declaration) {
        .function_decl => |function| .{
            .handle = handle,
            .stable_id = stable_id,
            .display_name = display_name,
            .signature = .{ .function = .{
                .parameters = try projectParameterTypes(allocator, function.parameters),
                .result = function.result,
                .effects = try allocator.dupe(Effect, function.effects),
            } },
        },
        .struct_decl => |structure| .{
            .handle = handle,
            .stable_id = stable_id,
            .display_name = display_name,
            .signature = .{ .structure = .{ .fields = try projectFieldTypes(allocator, structure.fields) } },
        },
        .external_function_decl => |function| .{
            .handle = handle,
            .stable_id = stable_id,
            .display_name = display_name,
            .signature = .{ .external_function = .{
                .parameters = try allocator.dupe(ScalarType, function.parameters),
                .result = function.result,
            } },
        },
    };
}

fn projectParameterTypes(allocator: std.mem.Allocator, parameters: []const Parameter) ![]const ScalarType {
    const types = try allocator.alloc(ScalarType, parameters.len);
    for (parameters, 0..) |parameter, index| types[index] = parameter.type;
    return types;
}

fn projectFieldTypes(allocator: std.mem.Allocator, fields: []const Field) ![]const ScalarType {
    const types = try allocator.alloc(ScalarType, fields.len);
    for (fields, 0..) |field, index| types[index] = field.type;
    return types;
}

/// Decodes v0 JSON into the canonical graph. JSON ends at this adapter.
pub fn decodeJsonSnapshot(backing_allocator: std.mem.Allocator, bytes: []const u8) !DecodedSnapshot {
    const arena = try backing_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer {
        arena.deinit();
        backing_allocator.destroy(arena);
    }
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

pub fn graphDigest(allocator: std.mem.Allocator, graph: Graph) ![64]u8 {
    const encoded = try encodeJsonSnapshot(allocator, graph);
    defer allocator.free(encoded);
    return snapshotDigest(encoded);
}

/// Applies a transaction to an isolated clone of `graph`. The supplied graph is
/// never modified. A candidate is returned only after all edits and canonical
/// graph validation succeed.
pub fn applyTransaction(
    backing_allocator: std.mem.Allocator,
    graph: Graph,
    transaction: Transaction,
) !DecodedSnapshot {
    const actual_digest = try graphDigest(backing_allocator, graph);
    if (!std.mem.eql(u8, &actual_digest, &transaction.base_digest)) return error.StaleBase;

    const encoded = try encodeJsonSnapshot(backing_allocator, graph);
    defer backing_allocator.free(encoded);
    var candidate = try decodeJsonSnapshot(backing_allocator, encoded);
    errdefer candidate.deinit();

    const declarations: []Declaration = @constCast(candidate.graph.declarations);
    for (transaction.renames) |rename| {
        var found = false;
        for (declarations) |*declaration| {
            if (std.mem.eql(u8, declaration.id(), rename.id)) {
                renameDeclaration(declaration, try candidate.arena.allocator().dupe(u8, rename.new_name));
                found = true;
                break;
            }
        }
        if (!found) return error.UnknownDeclaration;
    }
    if (try diagnoseGraph(candidate.graph, candidate.arena.allocator())) |_| return error.InvalidResultingGraph;
    return candidate;
}

fn renameDeclaration(declaration: *Declaration, new_name: []const u8) void {
    switch (declaration.*) {
        .struct_decl => |*value| value.name = new_name,
        .function_decl => |*value| value.name = new_name,
        .external_function_decl => |*value| value.name = new_name,
    }
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
    if (try diagnoseGraph(graph, allocator)) |result| return result.code;
}

/// Returns the first deterministic semantic diagnostic, including the smallest
/// graph object known to violate a rule. Allocation failures still use Zig
/// errors; semantic invalidity is represented by a Diagnostic.
pub fn diagnoseGraph(graph: Graph, allocator: std.mem.Allocator) !?Diagnostic {
    var ids = std.StringHashMap(void).init(allocator);
    defer ids.deinit();
    var names = std.StringHashMap(void).init(allocator);
    defer names.deinit();

    for (graph.declarations) |declaration| {
        if (ids.contains(declaration.id())) return diagnostic(error.DuplicateDeclarationId, declaration.id(), "declaration IDs are unique within a module");
        if (names.contains(declaration.name())) return diagnostic(error.DuplicateDeclarationName, declaration.id(), "declaration names are unique within a module");
        try ids.put(declaration.id(), {});
        try names.put(declaration.name(), {});
        switch (declaration) {
            .function_decl => |function| if (try diagnoseFunction(function, allocator)) |result| return result,
            else => {},
        }
    }
    return null;
}

/// Lowers the implemented, parameter-free `pub fn main() -> i32` subset to
/// LLVM IR. This is the first native-pipeline stage; linking is deliberately
/// separate from semantic validation.
pub fn lowerMainToLlvm(allocator: std.mem.Allocator, graph: Graph) ![]u8 {
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
    if (function.parameters.len != 0 or function.effects.len != 0 or function.result != .i32) return error.InvalidEntryFunction;

    var block: ?Block = null;
    for (function.body.blocks) |candidate| {
        if (std.mem.eql(u8, candidate.id, function.body.entry)) block = candidate;
    }
    const entry_block = block orelse return error.InvalidEntryFunction;

    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;
    try writer.writeAll("define i32 @main() {\nentry:\n");

    const LoweredValue = struct { index: usize, type: ScalarType };
    var values = std.StringHashMap(LoweredValue).init(allocator);
    defer values.deinit();
    var next_value: usize = 0;
    for (entry_block.operations) |operation| switch (operation) {
        .const_integer => |constant| {
            if (!isInteger(constant.type)) return error.InvalidEntryFunction;
            try writer.print("  %v{d} = add {s} 0, {d}\n", .{ next_value, llvmType(constant.type), constant.value });
            try values.put(constant.id, .{ .index = next_value, .type = constant.type });
            next_value += 1;
        },
        .wrapping_add => |add| {
            const left = values.get(add.left.operation_id) orelse return error.UnknownValue;
            const right = values.get(add.right.operation_id) orelse return error.UnknownValue;
            if (left.type != add.type or right.type != add.type) return error.BinaryOperandTypeMismatch;
            try writer.print("  %v{d} = add {s} %v{d}, %v{d}\n", .{ next_value, llvmType(add.type), left.index, right.index });
            try values.put(add.id, .{ .index = next_value, .type = add.type });
            next_value += 1;
        },
        .return_value => |return_value| {
            const value = values.get(return_value.value.operation_id) orelse return error.UnknownValue;
            if (value.type != .i32) return error.ReturnTypeMismatch;
            try writer.print("  ret i32 %v{d}\n}}\n", .{value.index});
            return output.toOwnedSlice();
        },
    };
    return error.InvalidEntryFunction;
}

fn llvmType(type_: ScalarType) []const u8 {
    return switch (type_) {
        .i8, .u8 => "i8",
        .i16, .u16 => "i16",
        .i32, .u32 => "i32",
        .i64, .u64 => "i64",
        else => unreachable,
    };
}

fn diagnoseFunction(function: FunctionDeclaration, allocator: std.mem.Allocator) !?Diagnostic {
    var block_ids = std.StringHashMap(void).init(allocator);
    defer block_ids.deinit();
    var operation_ids = std.StringHashMap(void).init(allocator);
    defer operation_ids.deinit();
    for (function.body.blocks) |block| {
        if (block_ids.contains(block.id)) return diagnostic(error.DuplicateBlockId, block.id, "block IDs are unique within a function");
        try block_ids.put(block.id, {});
        if (try diagnoseBlock(block, function.result, &operation_ids, allocator)) |result| return result;
    }
    if (!block_ids.contains(function.body.entry)) return diagnostic(error.MissingEntryBlock, function.id, "function entry names one of its blocks");
    return null;
}

fn diagnoseBlock(
    block: Block,
    function_result: ScalarType,
    operation_ids: *std.StringHashMap(void),
    allocator: std.mem.Allocator,
) !?Diagnostic {
    if (block.operations.len == 0) return diagnostic(error.MissingTerminator, block.id, "every block ends in a terminator");

    var values = std.StringHashMap(ScalarType).init(allocator);
    defer values.deinit();

    for (block.operations, 0..) |operation, index| {
        if (operation_ids.contains(operation.id())) return diagnostic(error.DuplicateOperationId, operation.id(), "operation IDs are unique within a function");
        try operation_ids.put(operation.id(), {});

        if (operation.isTerminator() and index + 1 != block.operations.len) return diagnostic(error.UnexpectedTerminator, operation.id(), "no operation follows a terminator");
        if (!operation.isTerminator() and index + 1 == block.operations.len) return diagnostic(error.MissingTerminator, operation.id(), "every block ends in a terminator");

        switch (operation) {
            .const_integer => |constant| {
                if (!integerFits(constant.value, constant.type)) return diagnostic(error.ConstantOutOfRange, constant.id, "integer constants fit their declared type");
                try values.put(constant.id, constant.type);
            },
            .wrapping_add => |add| {
                if (!isInteger(add.type)) return diagnostic(error.NonIntegerOperation, add.id, "wrapping addition has an integer type");
                const left_type = resolveLocalValue(&values, add.left) catch |err| return diagnostic(err, add.id, "an operand refers to an earlier local result at index zero");
                const right_type = resolveLocalValue(&values, add.right) catch |err| return diagnostic(err, add.id, "an operand refers to an earlier local result at index zero");
                if (left_type != add.type or right_type != add.type) return diagnostic(error.BinaryOperandTypeMismatch, add.id, "wrapping-add operands have the declared operation type");
                try values.put(add.id, add.type);
            },
            .return_value => |return_value| {
                const value_type = resolveLocalValue(&values, return_value.value) catch |err| return diagnostic(err, return_value.id, "a return refers to an earlier local result at index zero");
                if (value_type != function_result) return diagnostic(error.ReturnTypeMismatch, return_value.id, "a return value has the function result type");
            },
        }
    }
    return null;
}

fn diagnostic(code: ValidationError, object_id: []const u8, rule: []const u8) Diagnostic {
    return .{ .code = code, .object_id = object_id, .rule = rule };
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

/// Produces a debugger projection for the implemented graph subset. Function
/// names and visibility are linker metadata, so this view intentionally renders
/// anonymous function shapes rather than a conventional source declaration.
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
                "external function -> {s} @c({s}, {s})\n",
                .{ typeName(external_function.result), external_function.c_symbol, external_function.library },
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
    try writer.writeAll("function (");
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
        .unit => "unit",
        .boolean => "bool",
        .i8 => "i8",
        .i16 => "i16",
        .i32 => "i32",
        .i64 => "i64",
        .u8 => "u8",
        .u16 => "u16",
        .u32 => "u32",
        .u64 => "u64",
        .f32 => "f32",
        .f64 => "f64",
    };
}

fn representationName(repr: Representation) []const u8 {
    return switch (repr) {
        .native => "native",
        .c => "c",
    };
}

fn visibilityName(visibility: Visibility) []const u8 {
    return switch (visibility) {
        .private => "private",
        .public => "public",
    };
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
        \\function () -> i32 {
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

test "lowers the supported entry graph to LLVM IR" {
    const snapshot =
        \\{"protocol":"lil.wire/0","kind":"snapshot","optional_metadata":{},"body":{"id":"module.main","format_version":"lil.cpg/0","language_version":"0.1","target":"aarch64-macos-none","dependencies":[],"declarations":[{"kind":"function","id":"fn.main","name":"main","visibility":"public","parameters":[],"result":"i32","effects":[],"body":{"entry":"entry","blocks":[{"id":"entry","parameters":[],"operations":[{"op":"const","id":"op.left","type":"i32","value":20},{"op":"const","id":"op.right","type":"i32","value":22},{"op":"add.wrapping","id":"op.answer","type":"i32","left":{"operation_id":"op.left","result_index":0},"right":{"operation_id":"op.right","result_index":0}},{"op":"return","id":"term.return","value":{"operation_id":"op.answer","result_index":0}}]}]}}]}}
    ;
    var decoded = try decodeJsonSnapshot(std.testing.allocator, snapshot);
    defer decoded.deinit();
    const llvm_ir = try lowerMainToLlvm(std.testing.allocator, decoded.graph);
    defer std.testing.allocator.free(llvm_ir);
    try std.testing.expectEqualStrings(
        \\define i32 @main() {
        \\entry:
        \\  %v0 = add i32 0, 20
        \\  %v1 = add i32 0, 22
        \\  %v2 = add i32 %v0, %v1
        \\  ret i32 %v2
        \\}
        \\
    ,
        llvm_ir,
    );
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

test "transaction renames on an isolated graph with a matching base" {
    const snapshot =
        \\{"protocol":"lil.wire/0","kind":"snapshot","optional_metadata":{},"body":{"id":"module.main","format_version":"lil.cpg/0","language_version":"0.1","target":"aarch64-macos-none","dependencies":[],"declarations":[{"kind":"function","id":"fn.main","name":"main","visibility":"public","parameters":[],"result":"i32","effects":[],"body":{"entry":"entry","blocks":[{"id":"entry","parameters":[],"operations":[{"op":"const","id":"op.answer","type":"i32","value":42},{"op":"return","id":"term.return","value":{"operation_id":"op.answer","result_index":0}}]}]}}]}}
    ;
    var original = try decodeJsonSnapshot(std.testing.allocator, snapshot);
    defer original.deinit();
    const base_digest = try graphDigest(std.testing.allocator, original.graph);
    const renames = [_]RenameDeclaration{.{ .id = "fn.main", .new_name = "renamed_main" }};
    var candidate = try applyTransaction(std.testing.allocator, original.graph, .{
        .base_digest = base_digest,
        .renames = &renames,
    });
    defer candidate.deinit();

    try std.testing.expectEqualStrings("main", original.graph.declarations[0].name());
    try std.testing.expectEqualStrings("renamed_main", candidate.graph.declarations[0].name());
}

test "transaction rejects a stale base before applying edits" {
    const declarations = [_]Declaration{.{ .struct_decl = .{
        .id = "type.one",
        .name = "Original",
        .repr = .native,
        .fields = &.{},
    } }};
    const graph = Graph{ .id = "module.main", .target = .aarch64_macos, .dependencies = &.{}, .declarations = &declarations };
    const renames = [_]RenameDeclaration{.{ .id = "type.one", .new_name = "Changed" }};
    try std.testing.expectError(error.StaleBase, applyTransaction(std.testing.allocator, graph, .{
        .base_digest = [_]u8{0} ** 64,
        .renames = &renames,
    }));
    try std.testing.expectEqualStrings("Original", graph.declarations[0].name());
}

test "semantic token ABI decodes directly to a typed graph" {
    const tokens = [_]TokenId{
        TokenAbi.module_begin,
        TokenAbi.function_main_i32,
        TokenAbi.const_i32,
        try TokenAbi.literalI32(20),
        TokenAbi.const_i32,
        try TokenAbi.literalI32(22),
        TokenAbi.add_wrapping_i32,
        try TokenAbi.valueRef(0),
        try TokenAbi.valueRef(1),
        TokenAbi.return_i32,
        try TokenAbi.valueRef(2),
        TokenAbi.function_end,
        TokenAbi.module_end,
    };
    var decoded = try decodeTokenIds(std.testing.allocator, .aarch64_macos, &tokens);
    defer decoded.deinit();

    try std.testing.expectEqualStrings(token_abi_version, decoded.abi_version);
    try std.testing.expectEqual(tokens.len, decoded.token_count);
    try validateGraph(decoded.graph, std.testing.allocator);
    const result = try evaluateMain(decoded.graph, std.testing.allocator);
    try std.testing.expectEqual(IntegerValue{ .signed = 42 }, result);
    try std.testing.expectEqualStrings("latent.value.2", decoded.graph.declarations[0].function_decl.body.blocks[0].operations[2].id());
}

test "semantic decoder exposes typed next-token constraints" {
    var decoder = try SemanticDecoder.init(std.testing.allocator, .aarch64_macos, 16);
    defer decoder.deinit();

    switch (decoder.nextConstraint()) {
        .exact => |ids| try std.testing.expectEqualSlices(TokenId, &.{TokenAbi.module_begin}, ids),
        else => return error.TestUnexpectedResult,
    }
    try decoder.push(TokenAbi.module_begin);
    try decoder.push(TokenAbi.function_main_i32);
    try decoder.push(TokenAbi.const_i32);
    switch (decoder.nextConstraint()) {
        .i32_literal => {},
        else => return error.TestUnexpectedResult,
    }
    try decoder.push(try TokenAbi.literalI32(1));
    try decoder.push(TokenAbi.add_wrapping_i32);
    switch (decoder.nextConstraint()) {
        .i32_value_ref => |count| try std.testing.expectEqual(@as(u16, 1), count),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectError(error.InvalidValueReference, decoder.push(try TokenAbi.valueRef(1)));
    try decoder.push(try TokenAbi.valueRef(0));
}

test "semantic decoder rejects tokens outside the current grammar and type state" {
    var decoder = try SemanticDecoder.init(std.testing.allocator, .aarch64_macos, 8);
    defer decoder.deinit();
    try std.testing.expectError(error.UnexpectedToken, decoder.push(TokenAbi.const_i32));
    try decoder.push(TokenAbi.module_begin);
    try decoder.push(TokenAbi.function_main_i32);
    try decoder.push(TokenAbi.const_i32);
    try std.testing.expectError(error.InvalidLiteralToken, decoder.push(TokenAbi.value_ref_base));
}

test "token diagnostics preserve decoder state and target before rejection" {
    const tokens = [_]TokenId{ TokenAbi.module_begin, TokenAbi.function_main_i32, TokenAbi.const_i32, TokenAbi.value_ref_base };
    const decoder_diagnostic = (try diagnoseTokenIds(std.testing.allocator, .aarch64_macos, &tokens)).?;
    try std.testing.expectEqual(@as(usize, 3), decoder_diagnostic.token_offset);
    try std.testing.expectEqual(TokenAbi.value_ref_base, decoder_diagnostic.received.?);
    try std.testing.expectEqual(DecoderState.expect_i32_literal, decoder_diagnostic.state);
    try std.testing.expectEqual(Target.aarch64_macos, decoder_diagnostic.target);
    switch (decoder_diagnostic.expected) {
        .i32_literal => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(error.InvalidLiteralToken, decoder_diagnostic.failure);
}

test "scoped projections expose requested symbols, stable resolution, and token accounting" {
    const main_parameters = [_]Parameter{};
    const helper_parameters = [_]Parameter{.{ .name = "value", .type = .i32 }};
    const declarations = [_]Declaration{
        .{ .function_decl = .{
            .id = "fn.main",
            .name = "main",
            .visibility = .public,
            .parameters = &main_parameters,
            .result = .i32,
            .effects = &.{},
            .body = .{ .entry = "entry", .blocks = &.{} },
        } },
        .{ .function_decl = .{
            .id = "fn.helper",
            .name = "helper",
            .visibility = .private,
            .parameters = &helper_parameters,
            .result = .i64,
            .effects = &.{},
            .body = .{ .entry = "entry", .blocks = &.{} },
        } },
    };
    const graph = Graph{ .id = "module.projection", .target = .aarch64_macos, .dependencies = &.{}, .declarations = &declarations };
    const requested = [_][]const u8{"fn.helper"};
    var ledger = ProjectionLedger{};
    defer ledger.deinit(std.testing.allocator);
    var projection = try openScopedProjection(std.testing.allocator, &ledger, graph, &requested, .{
        .projection_tokens = 11,
        .retrieval_tokens = 7,
    });
    defer projection.deinit();

    try std.testing.expectEqualStrings("module.projection", projection.graph_id);
    try std.testing.expectEqual(@as(usize, 1), projection.symbols.len);
    try std.testing.expectEqualStrings("fn.helper", try projection.resolveHandle(1));
    try std.testing.expectError(error.UnknownModelHandle, projection.resolveHandle(2));
    switch (projection.symbols[0].signature) {
        .function => |signature| {
            try std.testing.expectEqual(@as(usize, 1), signature.parameters.len);
            try std.testing.expectEqual(ScalarType.i32, signature.parameters[0]);
            try std.testing.expectEqual(ScalarType.i64, signature.result);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(ProjectionAccounting{ .projection_tokens = 11, .retrieval_tokens = 7 }, ledger.totals());
}

test "scoped projections reject ambiguous or unknown stable identities" {
    const declarations = [_]Declaration{.{ .struct_decl = .{
        .id = "type.user",
        .name = "User",
        .repr = .native,
        .fields = &.{},
    } }};
    const graph = Graph{ .id = "module.projection", .target = .aarch64_macos, .dependencies = &.{}, .declarations = &declarations };
    var ledger = ProjectionLedger{};
    defer ledger.deinit(std.testing.allocator);
    const duplicate_ids = [_][]const u8{ "type.user", "type.user" };
    try std.testing.expectError(error.DuplicateProjectionSymbol, openScopedProjection(std.testing.allocator, &ledger, graph, &duplicate_ids, .{
        .projection_tokens = 0,
        .retrieval_tokens = 0,
    }));
    const missing_ids = [_][]const u8{"type.missing"};
    try std.testing.expectError(error.UnknownProjectionSymbol, openScopedProjection(std.testing.allocator, &ledger, graph, &missing_ids, .{
        .projection_tokens = 0,
        .retrieval_tokens = 0,
    }));
}

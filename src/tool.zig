const std = @import("std");
const Context = @import("Context.zig");
const Read = @import("tools/Read.zig");
const Create = @import("tools/Create.zig");
const Write = @import("tools/Write.zig");
const Ask = @import("tools/Ask.zig");

pub const Definition = struct {
    name: []const u8,
    description: []const u8,
    parameters: []const u8,
};

pub const definitions = [_]Definition{
    .{
        .name = "read",
        .description = "Read a text file and return its content.",
        .parameters =
        \\{"type":"object","properties":{"path":{"type":"string"}},
        \\ "required":["path"]}
        ,
    },
    .{
        .name = "create",
        .description = "Create a new file. Fails if the file already exists.",
        .parameters =
        \\{"type":"object","properties":{"path":{"type":"string"},
        \\ "content":{"type":"string"}},"required":["path","content"]}
        ,
    },
    .{
        .name = "write",
        .description = "Overwrite an existing file with new content.",
        .parameters =
        \\{"type":"object","properties":{"path":{"type":"string"},
        \\ "content":{"type":"string"}},"required":["path","content"]}
        ,
    },
    .{
        .name = "ask",
        .description = "Ask the user a question and return the answer.",
        .parameters =
        \\{"type":"object","properties":{"question":{"type":"string"}},
        \\ "required":["question"]}
        ,
    },
};

pub const Call = union(enum) {
    read: Read,
    create: Create,
    write: Write,
    ask: Ask,
};

pub fn parse(
    arena: std.mem.Allocator,
    name: []const u8,
    arguments_json: []const u8,
) !Call {
    if (std.mem.eql(u8, name, "read"))
        return .{ .read = try parseArguments(Read, arena, arguments_json) };
    if (std.mem.eql(u8, name, "create"))
        return .{ .create = try parseArguments(Create, arena, arguments_json) };
    if (std.mem.eql(u8, name, "write"))
        return .{ .write = try parseArguments(Write, arena, arguments_json) };
    if (std.mem.eql(u8, name, "ask"))
        return .{ .ask = try parseArguments(Ask, arena, arguments_json) };

    return error.UnknownTool;
}

pub fn needsApproval(call: Call) bool {
    return switch (call) {
        .read => Read.needs_approval,
        .create => Create.needs_approval,
        .write => Write.needs_approval,
        .ask => Ask.needs_approval,
    };
}

pub fn summary(arena: std.mem.Allocator, call: Call) ![]const u8 {
    return switch (call) {
        .read => |read| read.summary(arena),
        .create => |create| create.summary(arena),
        .write => |write| write.summary(arena),
        .ask => |ask| ask.summary(arena),
    };
}

pub fn run(context: Context, call: Call, user: anytype) ![]const u8 {
    return switch (call) {
        .read => |read| read.run(context),
        .create => |create| create.run(context),
        .write => |write| write.run(context),
        .ask => |ask| ask.run(context, user),
    };
}

fn parseArguments(
    comptime Arguments: type,
    arena: std.mem.Allocator,
    arguments_json: []const u8,
) !Arguments {
    return std.json.parseFromSliceLeaky(
        Arguments,
        arena,
        arguments_json,
        .{ .ignore_unknown_fields = true },
    );
}

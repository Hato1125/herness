const std = @import("std");
const Context = @import("Context.zig");
const llm = @import("llm.zig");
const Read = @import("tools/Read.zig");
const Create = @import("tools/Create.zig");
const Write = @import("tools/Write.zig");
const Ask = @import("tools/Ask.zig");
const List = @import("tools/List.zig");
const Diff = @import("tools/Diff.zig");
const Find = @import("tools/Find.zig");

pub const definitions = [_]llm.Tool{
    Read.definition,
    Create.definition,
    Write.definition,
    Ask.definition,
    List.definition,
    Diff.definition,
    Find.definition,
};

pub const Call = union(enum) {
    read: Read,
    create: Create,
    write: Write,
    ask: Ask,
    list: List,
    diff: Diff,
    find: Find,
};

pub fn parse(
    arena: std.mem.Allocator,
    name: []const u8,
    arguments_json: []const u8,
) !Call {
    const info = @typeInfo(Call).@"union";

    inline for (info.field_names, info.field_types) |tool_name, Arguments| {
        if (std.mem.eql(u8, name, tool_name)) {
            const arguments = try parseArguments(
                Arguments,
                arena,
                arguments_json,
            );
            return @unionInit(Call, tool_name, arguments);
        }
    }

    return error.UnknownTool;
}

pub fn needsApproval(call: Call) bool {
    return switch (call) {
        inline else => |tool| @TypeOf(tool).needs_approval,
    };
}

pub fn summary(arena: std.mem.Allocator, call: Call) ![]const u8 {
    return switch (call) {
        inline else => |tool| tool.summary(arena),
    };
}

pub fn run(context: Context, call: Call, user: anytype) ![]const u8 {
    return switch (call) {
        inline else => |tool| tool.run(context, user),
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

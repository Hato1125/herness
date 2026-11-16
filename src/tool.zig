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
    .{
        .name = "list",
        .description = "List the entries of a directory, including hidden ones.",
        .parameters =
        \\{"type":"object","properties":{"path":{"type":"string"}},
        \\ "required":["path"]}
        ,
    },
    .{
        .name = "diff",
        .description = "Compare two files and return a unified diff.",
        .parameters =
        \\{"type":"object","properties":{"old_path":{"type":"string"},
        \\ "new_path":{"type":"string"}},"required":["old_path","new_path"]}
        ,
    },
    .{
        .name = "find",
        .description = "Recursively find files under a directory whose names match a glob pattern.",
        .parameters =
        \\{"type":"object","properties":{"path":{"type":"string"},
        \\ "name":{"type":"string","description":"Glob such as *.cc. Defaults to *."}},
        \\ "required":["path"]}
        ,
    },
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
            const arguments = try parseArguments(Arguments, arena, arguments_json);
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

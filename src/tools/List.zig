const std = @import("std");
const Context = @import("../Context.zig");
const llm = @import("../llm.zig");
const List = @This();

pub const definition: llm.Tool = .{
    .name = "list",
    .description = "List the entries of a directory, including hidden ones.",
    .parameters =
    \\{"type":"object","properties":{"path":{"type":"string"}},
    \\ "required":["path"]}
    ,
};

pub const needs_approval = false;

path: []const u8,

pub fn summary(list: List, arena: std.mem.Allocator) ![]const u8 {
    _ = arena;
    return list.path;
}

pub fn run(list: List, context: Context, user: anytype) ![]const u8 {
    _ = user;
    const result = try std.process.run(context.arena, context.io, .{
        .argv = &.{ "ls", "-A", "--", list.path },
    });

    return std.mem.concat(context.arena, u8, &.{
        result.stdout,
        result.stderr,
    });
}

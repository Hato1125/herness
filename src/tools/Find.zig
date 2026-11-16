const std = @import("std");
const Context = @import("../Context.zig");
const llm = @import("../llm.zig");
const Find = @This();

pub const definition: llm.Tool = .{
    .name = "find",
    .description = "Recursively find files under a directory whose names match a glob pattern.",
    .parameters =
    \\{"type":"object","properties":{"path":{"type":"string"},
    \\ "name":{"type":"string","description":"Glob such as *.cc. Defaults to *."}},
    \\ "required":["path"]}
    ,
};

pub const needs_approval = false;

path: []const u8,
name: []const u8 = "*",

pub fn summary(find: Find, arena: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s} -name {s}", .{ find.path, find.name });
}

pub fn run(find: Find, context: Context, user: anytype) ![]const u8 {
    _ = user;
    const result = try std.process.run(context.arena, context.io, .{
        .argv = &.{ "find", find.path, "-name", find.name },
    });

    return std.mem.concat(context.arena, u8, &.{
        result.stdout,
        result.stderr,
    });
}

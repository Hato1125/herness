const std = @import("std");
const Context = @import("../Context.zig");
const Create = @This();

pub const needs_approval = true;

path: []const u8,
content: []const u8,

pub fn summary(create: Create, arena: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s} ({d} bytes)", .{
        create.path, create.content.len,
    });
}

pub fn run(create: Create, context: Context, user: anytype) ![]const u8 {
    _ = user;
    try std.Io.Dir.cwd().writeFile(context.io, .{
        .sub_path = create.path,
        .data = create.content,
        .flags = .{ .exclusive = true },
    });

    return "ok";
}

const std = @import("std");
const Context = @import("../Context.zig");
const Diff = @This();

pub const needs_approval = false;

old_path: []const u8,
new_path: []const u8,

pub fn summary(diff: Diff, arena: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s} {s}", .{ diff.old_path, diff.new_path });
}

pub fn run(diff: Diff, context: Context) ![]const u8 {
    const result = try std.process.run(context.arena, context.io, .{
        .argv = &.{ "diff", "-u", "--", diff.old_path, diff.new_path },
    });

    return std.mem.concat(context.arena, u8, &.{
        result.stdout,
        result.stderr,
    });
}

const std = @import("std");
const Context = @import("../Context.zig");
const Write = @This();

pub const needs_approval = true;

path: []const u8,
content: []const u8,

pub fn summary(write: Write, arena: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s} ({d} bytes)", .{
        write.path, write.content.len,
    });
}

pub fn run(write: Write, context: Context) ![]const u8 {
    var file = try std.Io.Dir.cwd().openFile(
        context.io,
        write.path,
        .{ .mode = .write_only },
    );
    defer file.close(context.io);

    try file.setLength(context.io, 0);
    try file.writeStreamingAll(context.io, write.content);

    return "ok";
}

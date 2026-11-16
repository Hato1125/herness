const std = @import("std");
const Context = @import("../Context.zig");
const llm = @import("../llm.zig");
const Write = @This();

pub const definition: llm.Tool = .{
    .name = "write",
    .description = "Overwrite an existing file with new content.",
    .parameters =
    \\{"type":"object","properties":{"path":{"type":"string"},
    \\ "content":{"type":"string"}},"required":["path","content"]}
    ,
};

pub const needs_approval = true;

path: []const u8,
content: []const u8,

pub fn summary(write: Write, arena: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s} ({d} bytes)", .{
        write.path, write.content.len,
    });
}

pub fn run(write: Write, context: Context, user: anytype) ![]const u8 {
    _ = user;
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

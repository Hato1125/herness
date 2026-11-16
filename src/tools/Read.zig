const std = @import("std");
const Context = @import("../Context.zig");
const Read = @This();

const max_file_bytes = 1024 * 1024;

pub const needs_approval = false;

path: []const u8,

pub fn summary(read: Read, arena: std.mem.Allocator) ![]const u8 {
    _ = arena;
    return read.path;
}

pub fn run(read: Read, context: Context, user: anytype) ![]const u8 {
    _ = user;
    return std.Io.Dir.cwd().readFileAlloc(
        context.io,
        read.path,
        context.arena,
        .limited(max_file_bytes),
    );
}

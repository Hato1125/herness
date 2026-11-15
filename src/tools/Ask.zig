const std = @import("std");
const Context = @import("../Context.zig");
const Ask = @This();

pub const needs_approval = false;

question: []const u8,

pub fn summary(ask: Ask, arena: std.mem.Allocator) ![]const u8 {
    _ = arena;
    return ask.question;
}

pub fn run(ask: Ask, context: Context, user: anytype) ![]const u8 {
    return user.ask(context.arena, ask.question);
}

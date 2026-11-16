const std = @import("std");
const Context = @import("../Context.zig");
const llm = @import("../llm.zig");
const Ask = @This();

pub const definition: llm.Tool = .{
    .name = "ask",
    .description = "Ask the user a question and return the answer.",
    .parameters =
    \\{"type":"object","properties":{"question":{"type":"string"}},
    \\ "required":["question"]}
    ,
};

pub const needs_approval = false;

question: []const u8,

pub fn summary(ask: Ask, arena: std.mem.Allocator) ![]const u8 {
    _ = arena;
    return ask.question;
}

pub fn run(ask: Ask, context: Context, user: anytype) ![]const u8 {
    return user.ask(context.arena, ask.question);
}

const std = @import("std");
const Context = @import("../Context.zig");
const llm = @import("../llm.zig");
const acp = @import("../protocols/acp.zig");
const Gemini = @This();

pub const name = "Gemini";
pub const icon = "\u{f0ae2}";

pub const Config = struct {
    argv: []const []const u8 = &.{ "agy", "acp" },
    model: ?[]const u8 = null,
    effort: ?[]const u8 = null,
};

config: Config,
client: ?*acp.Client = null,

pub fn init(
    arena: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    config: Config,
) !Gemini {
    _ = arena;
    _ = env;
    return .{ .config = config };
}

pub fn connect(gemini: *Gemini, context: Context) !void {
    const client = try acp.Client.start(context, gemini.config.argv);
    gemini.client = client;

    if (gemini.config.model) |model|
        try client.setConfig(context, "model", model);
    if (gemini.config.effort) |effort|
        try client.setConfig(context, "thought_level", effort);
}

pub fn complete(
    gemini: *Gemini,
    context: Context,
    messages: []const llm.Message,
    tools: []const llm.Tool,
    listener: anytype,
) !llm.Message {
    _ = tools;
    const client = gemini.client orelse return error.NotConnected;
    const last = messages[messages.len - 1];

    return client.prompt(context, last.content, listener);
}

pub fn stop(gemini: *Gemini, context: Context) void {
    if (gemini.client) |client| client.stop(context);
}

pub const commands = struct {
    pub const model = struct {
        pub const description = "Switch the model among those the agent lists.";

        pub fn run(gemini: *Gemini, context: Context, args: []const u8) !void {
            const client = gemini.client orelse return error.NotConnected;
            try client.setConfig(context, "model", args);
        }
    };

    pub const effort = struct {
        pub const description = "Set the thought level among those the agent lists.";

        pub fn run(gemini: *Gemini, context: Context, args: []const u8) !void {
            const client = gemini.client orelse return error.NotConnected;
            try client.setConfig(context, "thought_level", args);
        }
    };
};

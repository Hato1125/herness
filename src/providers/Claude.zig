const std = @import("std");
const Context = @import("../Context.zig");
const llm = @import("../llm.zig");
const acp = @import("../protocols/acp.zig");
const Claude = @This();

pub const name = "Claude";
pub const icon = "\u{ec82}";

pub const Config = struct {
    argv: []const []const u8 = &.{"claude-agent-acp"},
    model: ?[]const u8 = null,
    effort: ?[]const u8 = null,
};

config: Config,
client: ?*acp.Client = null,

pub fn init(
    arena: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    config: Config,
) !Claude {
    _ = arena;
    _ = env;
    return .{ .config = config };
}

pub fn connect(claude: *Claude, context: Context) !void {
    const client = try acp.Client.start(context, claude.config.argv);
    claude.client = client;

    if (claude.config.model) |model|
        try client.setConfig(context, "model", model);
    if (claude.config.effort) |effort|
        try client.setConfig(context, "thought_level", effort);
}

pub fn complete(
    claude: *Claude,
    context: Context,
    messages: []const llm.Message,
    tools: []const llm.Tool,
    listener: anytype,
) !llm.Message {
    _ = tools;
    const client = claude.client orelse return error.NotConnected;
    const last = messages[messages.len - 1];

    return client.prompt(context, last.content, listener);
}

pub fn stop(claude: *Claude, context: Context) void {
    if (claude.client) |client| client.stop(context);
}

pub const commands = struct {
    pub const model = struct {
        pub const description = "Switch the model among those the agent lists.";

        pub fn run(claude: *Claude, context: Context, args: []const u8) !void {
            const client = claude.client orelse return error.NotConnected;
            try client.setConfig(context, "model", args);
        }
    };

    pub const effort = struct {
        pub const description = "Set the thought level among those the agent lists.";

        pub fn run(claude: *Claude, context: Context, args: []const u8) !void {
            const client = claude.client orelse return error.NotConnected;
            try client.setConfig(context, "thought_level", args);
        }
    };
};

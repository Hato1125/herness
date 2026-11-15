const std = @import("std");
const openai = @import("protocols/openai.zig");
const Context = @import("Context.zig");
const Llama = @import("providers/Llama.zig");
const Ollama = @import("providers/Ollama.zig");

pub const Message = openai.Message;

/// What happens while a reply is arriving.
pub const Event = union(enum) {
    /// The model started reasoning before it answers.
    thinking,
    /// A piece of the answer text.
    text: []const u8,
};

pub const Kind = enum {
    llama,
    ollama,
};

pub const Provider = union(Kind) {
    llama: Llama,
    ollama: Ollama,

    pub fn init(
        kind: Kind,
        arena: std.mem.Allocator,
        env: *const std.process.Environ.Map,
        model: ?[]const u8,
    ) !Provider {
        return switch (kind) {
            .llama => .{ .llama = try Llama.init(arena, env, model) },
            .ollama => .{ .ollama = try Ollama.init(arena, env, model) },
        };
    }

    pub fn connect(provider: *Provider, context: Context) !void {
        return switch (provider.*) {
            .llama => |*llama| llama.connect(context),
            .ollama => |*ollama| ollama.connect(context),
        };
    }

    pub fn complete(
        provider: *Provider,
        context: Context,
        messages: []const Message,
        listener: anytype,
    ) !Message {
        return switch (provider.*) {
            .llama => |*llama| llama.complete(context, messages, listener),
            .ollama => |*ollama| ollama.complete(context, messages, listener),
        };
    }

    pub fn stop(provider: *Provider, context: Context) void {
        switch (provider.*) {
            .llama => |*llama| llama.stop(context),
            .ollama => |*ollama| ollama.stop(context),
        }
    }
};

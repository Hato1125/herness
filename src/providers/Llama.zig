const std = @import("std");
const Context = @import("../Context.zig");
const llm = @import("../llm.zig");
const openai = @import("../protocols/openai.zig");
const Llama = @This();

pub const name = "llama";
pub const icon = "\u{f06a9}";

const default_host = "127.0.0.1";
const default_port = "8080";
const ready_timeout_ms = 300_000;
const health_poll_interval_ms = 500;

pub const Config = struct {
    path: ?[]const u8 = null,
    effort: ?Effort = null,
};

pub const Effort = enum {
    low,
    medium,
    high,
};

url: []const u8,
port: []const u8,
path: ?[]const u8,
effort: ?Effort,

/// Set only when this process started llama-server and must stop it.
child: ?std.process.Child = null,

pub fn init(
    arena: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    config: Config,
) !Llama {
    const host = env.get("LLAMA_HOST") orelse default_host;
    const port = env.get("LLAMA_PORT") orelse default_port;

    return .{
        .url = try std.fmt.allocPrint(arena, "http://{s}:{s}", .{ host, port }),
        .port = port,
        .path = config.path,
        .effort = config.effort,
    };
}

pub fn connect(llama: *Llama, context: Context) !void {
    if (ok(context, try llama.healthUrl(context))) return;

    try llama.spawn(context);
}

pub fn complete(
    llama: *Llama,
    context: Context,
    messages: []const llm.Message,
    tools: []const llm.Tool,
    listener: anytype,
) !llm.Message {
    return openai.complete(
        context,
        llama.url,
        .{ .chat_template_kwargs = if (llama.effort) |effort| .{ .reasoning_effort = @tagName(effort) } else null },
        messages,
        tools,
        listener,
    );
}

pub fn stop(llama: *Llama, context: Context) void {
    if (llama.child) |*child| child.kill(context.io);
    llama.child = null;
}

pub const commands = struct {
    pub const model = struct {
        pub const description = "Restart llama-server with another GGUF file.";

        pub fn run(llama: *Llama, context: Context, args: []const u8) !void {
            if (llama.child == null) return error.ExternalServer;
            if (args.len == 0) return error.ModelNotSpecified;

            llama.stop(context);
            llama.path = try context.arena.dupe(u8, args);
            try llama.spawn(context);
        }
    };

    pub const effort = struct {
        pub const description = "Set reasoning effort: low, medium, high, or empty to reset.";

        pub fn run(llama: *Llama, context: Context, args: []const u8) !void {
            _ = context;
            llama.effort = try parseEffort(args);
        }
    };
};

fn spawn(llama: *Llama, context: Context) !void {
    const path = llama.path orelse return error.ModelNotSpecified;
    const health_url = try llama.healthUrl(context);

    // --jinja is required for llama-server to accept the tools field.
    llama.child = try std.process.spawn(context.io, .{
        .argv = &.{
            "llama-server",
            "-m",
            path,
            "--port",
            llama.port,
            "--jinja",
            "--device",
            "Vulkan0",
        },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });

    for (0..ready_timeout_ms / health_poll_interval_ms) |_| {
        if (ok(context, health_url)) return;

        try context.io.sleep(.fromMilliseconds(health_poll_interval_ms), .awake);
    }

    return error.ServerStartTimeout;
}

fn healthUrl(llama: *const Llama, context: Context) ![]const u8 {
    return std.mem.concat(context.arena, u8, &.{ llama.url, "/health" });
}

fn parseEffort(args: []const u8) !?Effort {
    if (args.len == 0) return null;

    return std.meta.stringToEnum(Effort, args) orelse error.UnknownEffort;
}

fn ok(context: Context, url: []const u8) bool {
    const result = context.client.fetch(.{
        .location = .{ .url = url },
        .keep_alive = false,
    }) catch return false;

    return result.status == .ok;
}

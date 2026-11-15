const std = @import("std");
const Context = @import("../Context.zig");
const openai = @import("../protocols/openai.zig");
const Llama = @This();

const default_host = "127.0.0.1";
const default_port = "8080";
const ready_timeout_ms = 300_000;
const health_poll_interval_ms = 500;

url: []const u8,
port: []const u8,
path: ?[]const u8,

/// Set only when this process started llama-server and must stop it.
child: ?std.process.Child = null,

pub fn init(
    arena: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    path: ?[]const u8,
) !Llama {
    const host = env.get("LLAMA_HOST") orelse default_host;
    const port = env.get("LLAMA_PORT") orelse default_port;

    return .{
        .url = try std.fmt.allocPrint(arena, "http://{s}:{s}", .{ host, port }),
        .port = port,
        .path = path,
    };
}

pub fn connect(llama: *Llama, context: Context) !void {
    const health_url = try std.mem.concat(context.arena, u8, &.{
        llama.url, "/health",
    });

    if (ok(context, health_url)) return;

    const path = llama.path orelse return error.ModelNotSpecified;

    // --jinja is required for llama-server to accept the tools field.
    llama.child = try std.process.spawn(context.io, .{
        .argv = &.{
            "llama-server",
            "-m",
            path,
            "--port",
            llama.port,
            "--jinja",
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

pub fn complete(
    llama: *Llama,
    context: Context,
    messages: []const openai.Message,
    listener: anytype,
) !openai.Message {
    return openai.complete(context, llama.url, null, messages, listener);
}

pub fn stop(llama: *Llama, context: Context) void {
    if (llama.child) |*child| child.kill(context.io);
}

fn ok(context: Context, url: []const u8) bool {
    const result = context.client.fetch(.{
        .location = .{ .url = url },
        .keep_alive = false,
    }) catch return false;

    return result.status == .ok;
}

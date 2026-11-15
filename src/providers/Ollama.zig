const std = @import("std");
const Context = @import("../Context.zig");
const openai = @import("../protocols/openai.zig");
const Ollama = @This();

const default_host = "127.0.0.1";
const default_port = "11434";
const ready_timeout_ms = 30_000;
const version_poll_interval_ms = 500;

url: []const u8,
model: ?[]const u8,
serve_env: std.process.Environ.Map,

/// Set only when this process started ollama and must stop it.
child: ?std.process.Child = null,

pub fn init(
    arena: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    model: ?[]const u8,
) !Ollama {
    const host = env.get("OLLAMA_HOST") orelse default_host;
    const port = env.get("OLLAMA_PORT") orelse default_port;
    const address = try std.fmt.allocPrint(arena, "{s}:{s}", .{ host, port });

    // ollama serve takes its address from OLLAMA_HOST instead of an argument.
    var serve_env = try env.clone(arena);
    try serve_env.put("OLLAMA_HOST", address);

    return .{
        .url = try std.mem.concat(arena, u8, &.{ "http://", address }),
        .model = model,
        .serve_env = serve_env,
    };
}

pub fn connect(ollama: *Ollama, context: Context) !void {
    if (ollama.model == null) return error.ModelNotSpecified;

    const version_url = try std.mem.concat(context.arena, u8, &.{
        ollama.url, "/api/version",
    });

    if (ok(context, version_url)) return;

    ollama.child = try std.process.spawn(context.io, .{
        .argv = &.{
            "ollama",
            "serve",
        },
        .environ_map = &ollama.serve_env,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });

    for (0..ready_timeout_ms / version_poll_interval_ms) |_| {
        if (ok(context, version_url)) return;

        try context.io.sleep(.fromMilliseconds(version_poll_interval_ms), .awake);
    }

    return error.ServerStartTimeout;
}

pub fn complete(
    ollama: *Ollama,
    context: Context,
    messages: []const openai.Message,
    listener: anytype,
) !openai.Message {
    return openai.complete(
        context,
        ollama.url,
        ollama.model,
        messages,
        listener,
    );
}

pub fn stop(ollama: *Ollama, context: Context) void {
    if (ollama.child) |*child| child.kill(context.io);
}

fn ok(context: Context, url: []const u8) bool {
    const result = context.client.fetch(.{
        .location = .{ .url = url },
        .keep_alive = false,
    }) catch return false;

    return result.status == .ok;
}

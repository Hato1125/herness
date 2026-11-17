const std = @import("std");
const Io = std.Io;
const json = std.json;
const Context = @import("../Context.zig");
const llm = @import("../llm.zig");

const protocol_version = 1;

const auth_required_code = -32000;
const method_not_found_code = -32601;

/// A session with an Agent Client Protocol agent running as a child process.
/// The agent keeps the conversation and runs its own tools.
pub const Client = struct {
    child: std.process.Child,
    writer: Io.File.Writer,
    reader: Io.File.Reader,
    write_buffer: [4096]u8 = undefined,
    read_buffer: [64 * 1024]u8 = undefined,
    next_id: i64 = 0,
    session_id: []const u8 = "",
    config_options: []const ConfigOption = &.{},
    reply: Io.Writer.Allocating,
    thinking: bool = false,

    /// Spawns the agent, then sends initialize and session/new.
    /// The agent must already be signed in through its own CLI.
    pub fn start(context: Context, argv: []const []const u8) !*Client {
        const arena = context.arena;

        // The readers and writers point into the client, so it must not move.
        const client = try arena.create(Client);
        client.* = .{
            .child = try std.process.spawn(context.io, .{
                .argv = argv,
                .stdin = .pipe,
                .stdout = .pipe,
                .stderr = .ignore,
            }),
            .writer = undefined,
            .reader = undefined,
            .reply = .init(arena),
        };
        errdefer client.stop(context);

        client.writer = client.child.stdin.?.writerStreaming(
            context.io,
            &client.write_buffer,
        );
        client.reader = client.child.stdout.?.readerStreaming(
            context.io,
            &client.read_buffer,
        );

        // No fs or terminal capability is offered, so the agent uses its own.
        const initialized = try client.call(context, "initialize", .{
            .protocolVersion = protocol_version,
            .clientCapabilities = ClientCapabilities{},
            .clientInfo = .{
                .name = "herness",
                .version = "0.0.0",
            },
        }, InitializeResult, Silent{});
        if (initialized.protocolVersion != protocol_version) {
            return error.UnsupportedProtocolVersion;
        }

        const session = try client.call(context, "session/new", .{
            .cwd = try std.process.currentPathAlloc(context.io, arena),
            .mcpServers = &[_]json.Value{},
        }, NewSessionResult, Silent{});

        client.session_id = session.sessionId;
        client.config_options = session.configOptions orelse &.{};

        return client;
    }

    /// Sends text as the next user message and streams the reply to the
    /// listener until the agent ends its turn.
    pub fn prompt(
        client: *Client,
        context: Context,
        text: []const u8,
        listener: anytype,
    ) !llm.Message {
        client.reply = .init(context.arena);
        client.thinking = false;

        _ = try client.call(context, "session/prompt", .{
            .sessionId = client.session_id,
            .prompt = &[_]TextBlock{.{ .text = text }},
        }, PromptResult, listener);

        return .{
            .role = .assistant,
            .content = client.reply.written(),
        };
    }

    /// Sets the session option of the given category, such as "model" or
    /// "thought_level". The agent decides which values it accepts.
    pub fn setConfig(
        client: *Client,
        context: Context,
        category: []const u8,
        value: []const u8,
    ) !void {
        const option = client.findConfig(category) orelse
            return error.UnsupportedConfig;

        const result = try client.call(context, "session/set_config_option", .{
            .sessionId = client.session_id,
            .configId = option.id,
            .value = value,
        }, SetConfigResult, Silent{});

        client.config_options = result.configOptions;
    }

    pub fn stop(client: *Client, context: Context) void {
        client.child.kill(context.io);
    }

    fn findConfig(client: *const Client, category: []const u8) ?ConfigOption {
        for (client.config_options) |option| {
            const option_category = option.category orelse continue;
            if (std.mem.eql(u8, option_category, category)) return option;
        }

        return null;
    }

    /// Sends a request and handles what the agent sends until its response.
    fn call(
        client: *Client,
        context: Context,
        method: []const u8,
        params: anytype,
        comptime Result: type,
        listener: anytype,
    ) !Result {
        const id = client.next_id;
        client.next_id += 1;

        try client.send(context, .{
            .jsonrpc = "2.0",
            .id = id,
            .method = method,
            .params = params,
        });

        while (true) {
            const message = try client.receive(context);

            if (message.method) |name| {
                try client.handle(context, message, name, listener);
                continue;
            }

            const response_id = message.id orelse continue;
            if (response_id != .integer or response_id.integer != id) continue;

            if (message.@"error") |err| {
                if (err.code == auth_required_code) return error.AuthRequired;
                return error.RequestFailed;
            }

            return json.parseFromValueLeaky(
                Result,
                context.arena,
                message.result orelse .null,
                .{ .ignore_unknown_fields = true },
            );
        }
    }

    fn handle(
        client: *Client,
        context: Context,
        message: Incoming,
        method: []const u8,
        listener: anytype,
    ) !void {
        const params = message.params orelse .null;

        if (std.mem.eql(u8, method, "session/update")) {
            const notification = try parseValue(UpdateParams, context, params);
            return client.onUpdate(notification.update, listener);
        }

        // Notifications have no id and need no answer.
        const id = message.id orelse return;

        if (std.mem.eql(u8, method, "session/request_permission")) {
            const request = try parseValue(PermissionParams, context, params);
            const allowed = listener.approve(.{
                .title = request.toolCall.title orelse "",
            });

            return client.send(context, .{
                .jsonrpc = "2.0",
                .id = id,
                .result = .{ .outcome = chooseOutcome(request.options, allowed) },
            });
        }

        try client.send(context, .{
            .jsonrpc = "2.0",
            .id = id,
            .@"error" = .{
                .code = method_not_found_code,
                .message = "Method not found",
            },
        });
    }

    fn onUpdate(client: *Client, update: Update, listener: anytype) !void {
        const kind = update.sessionUpdate;

        if (std.mem.eql(u8, kind, "agent_message_chunk")) {
            const text = textOf(update.content) orelse return;
            try client.reply.writer.writeAll(text);
            listener.onEvent(.{ .text = text });
        } else if (std.mem.eql(u8, kind, "agent_thought_chunk")) {
            if (client.thinking) return;
            client.thinking = true;
            listener.onEvent(.thinking);
        } else if (std.mem.eql(u8, kind, "tool_call")) {
            listener.onEvent(.{ .tool = update.title orelse "" });
        } else if (std.mem.eql(u8, kind, "config_option_update")) {
            client.config_options = update.configOptions orelse return;
        }
    }

    fn send(client: *Client, context: Context, message: anytype) !void {
        const line = try json.Stringify.valueAlloc(
            context.arena,
            message,
            .{ .emit_null_optional_fields = false },
        );

        // ACP separates messages with newlines, and JSON output has none.
        const writer = &client.writer.interface;
        try writer.writeAll(line);
        try writer.writeByte('\n');
        try writer.flush();
    }

    fn receive(client: *Client, context: Context) !Incoming {
        const reader = &client.reader.interface;
        var line: Io.Writer.Allocating = .init(context.arena);

        _ = reader.streamDelimiter(&line.writer, '\n') catch |err| switch (err) {
            error.EndOfStream => return error.AgentExited,
            else => |e| return e,
        };
        reader.toss(1);

        return json.parseFromSliceLeaky(Incoming, context.arena, line.written(), .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
    }
};

const Silent = struct {
    pub fn onEvent(silent: Silent, event: anytype) void {
        _ = silent;
        _ = event;
    }

    pub fn approve(silent: Silent, approval: anytype) bool {
        _ = silent;
        _ = approval;
        return false;
    }
};

const Incoming = struct {
    id: ?json.Value = null,
    method: ?[]const u8 = null,
    params: ?json.Value = null,
    result: ?json.Value = null,
    @"error": ?Error = null,

    const Error = struct {
        code: i64,
    };
};

const ConfigOption = struct {
    id: []const u8,
    category: ?[]const u8 = null,
};

const ClientCapabilities = struct {
    fs: FileSystem = .{},
    terminal: bool = false,

    const FileSystem = struct {
        readTextFile: bool = false,
        writeTextFile: bool = false,
    };
};

const InitializeResult = struct {
    protocolVersion: i64,
};

const NewSessionResult = struct {
    sessionId: []const u8,
    configOptions: ?[]const ConfigOption = null,
};

const PromptResult = struct {
    stopReason: []const u8,
};

const SetConfigResult = struct {
    configOptions: []const ConfigOption,
};

const TextBlock = struct {
    type: []const u8 = "text",
    text: []const u8,
};

const UpdateParams = struct {
    update: Update,
};

const Update = struct {
    sessionUpdate: []const u8,
    /// A content block for chunks, or a list of them for tool calls.
    content: ?json.Value = null,
    title: ?[]const u8 = null,
    configOptions: ?[]const ConfigOption = null,
};

const PermissionParams = struct {
    toolCall: ToolCall = .{},
    options: []const PermissionOption,

    const ToolCall = struct {
        title: ?[]const u8 = null,
    };
};

const PermissionOption = struct {
    optionId: []const u8,
    kind: []const u8,
};

const Outcome = struct {
    outcome: []const u8,
    optionId: ?[]const u8 = null,
};

/// Picks the one-time option for the answer, so the agent does not
/// remember it for later calls.
fn chooseOutcome(options: []const PermissionOption, allowed: bool) Outcome {
    const wanted = if (allowed) "allow_once" else "reject_once";

    for (options) |option| {
        if (std.mem.eql(u8, option.kind, wanted)) {
            return .{
                .outcome = "selected",
                .optionId = option.optionId,
            };
        }
    }

    return .{ .outcome = "cancelled" };
}

fn textOf(content: ?json.Value) ?[]const u8 {
    const block = switch (content orelse return null) {
        .object => |object| object,
        else => return null,
    };

    const text = block.get("text") orelse return null;
    return switch (text) {
        .string => |string| string,
        else => null,
    };
}

fn parseValue(comptime T: type, context: Context, value: json.Value) !T {
    return json.parseFromValueLeaky(T, context.arena, value, .{
        .ignore_unknown_fields = true,
    });
}

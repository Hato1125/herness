const std = @import("std");
const Io = std.Io;
const json = std.json;
const Context = @import("../Context.zig");
const llm = @import("../llm.zig");
const Message = llm.Message;
const ToolCall = llm.ToolCall;

pub fn complete(
    context: Context,
    url: []const u8,
    model: ?[]const u8,
    messages: []const Message,
    tools: []const llm.Tool,
    listener: anytype,
) !Message {
    const arena = context.arena;

    const request: Request = .{
        .model = model,
        .messages = messages,
        .tools = try buildTools(arena, tools),
    };

    const request_json = try json.Stringify.valueAlloc(
        arena,
        request,
        .{ .emit_null_optional_fields = false },
    );

    const endpoint = try std.mem.concat(arena, u8, &.{ url, "/v1/chat/completions" });

    // The stream is read line by line, so it must not arrive compressed.
    var http_request = try context.client.request(.POST, try std.Uri.parse(endpoint), .{
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .accept_encoding = .omit,
        },
        .keep_alive = false,
        .redirect_behavior = .unhandled,
    });
    defer http_request.deinit();

    try http_request.sendBodyComplete(request_json);

    var response = try http_request.receiveHead(&.{});
    if (response.head.status != .ok) return error.RequestFailed;

    var transfer_buffer: [4096]u8 = undefined;

    return readStream(context, response.reader(&transfer_buffer), listener);
}

const Request = struct {
    model: ?[]const u8,
    stream: bool = true,
    messages: []const Message,
    tools: []const WireTool,
};

const WireTool = struct {
    type: []const u8 = "function",
    function: Function,

    const Function = struct {
        name: []const u8,
        description: []const u8,
        parameters: json.Value,
    };
};

const Chunk = struct {
    choices: []const Choice = &.{},
    @"error": ?json.Value = null,

    const Choice = struct {
        delta: ?Delta = null,
    };

    const Delta = struct {
        reasoning_content: ?[]const u8 = null,
        content: ?[]const u8 = null,
        tool_calls: ?[]const ToolCallPart = null,
    };

    const ToolCallPart = struct {
        index: usize = 0,
        id: ?[]const u8 = null,
        function: Function = .{},

        const Function = struct {
            name: ?[]const u8 = null,
            arguments: ?[]const u8 = null,
        };
    };
};

const PendingCall = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    arguments: std.ArrayList(u8) = .empty,
};

fn buildTools(
    arena: std.mem.Allocator,
    definitions: []const llm.Tool,
) ![]const WireTool {
    const tools = try arena.alloc(WireTool, definitions.len);

    for (tools, definitions) |*entry, definition| {
        const parameters = try json.parseFromSliceLeaky(
            json.Value,
            arena,
            definition.parameters,
            .{},
        );

        entry.* = .{
            .function = .{
                .name = definition.name,
                .description = definition.description,
                .parameters = parameters,
            },
        };
    }

    return tools;
}

fn readStream(context: Context, reader: *Io.Reader, listener: anytype) !Message {
    const arena = context.arena;

    var line: Io.Writer.Allocating = .init(arena);
    var content: Io.Writer.Allocating = .init(arena);
    var calls: std.ArrayList(PendingCall) = .empty;
    var thinking = false;

    while (true) {
        line.clearRetainingCapacity();
        _ = reader.streamDelimiter(&line.writer, '\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        reader.toss(1);

        const data = eventData(line.written()) orelse continue;
        if (std.mem.eql(u8, data, "[DONE]")) break;

        // The line buffer is reused, so the parsed strings must be copies.
        const chunk = try json.parseFromSliceLeaky(Chunk, arena, data, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        if (chunk.@"error" != null) return error.RequestFailed;
        if (chunk.choices.len == 0) continue;

        const delta = chunk.choices[0].delta orelse continue;

        const thought = delta.reasoning_content orelse "";
        if (thought.len > 0 and !thinking) {
            thinking = true;
            listener.onEvent(.thinking);
        }

        const text = delta.content orelse "";
        if (text.len > 0) {
            try content.writer.writeAll(text);
            listener.onEvent(.{ .text = text });
        }

        const parts: []const Chunk.ToolCallPart = delta.tool_calls orelse &.{};

        for (parts) |part| {
            while (calls.items.len <= part.index) try calls.append(arena, .{});
            const call = &calls.items[part.index];

            const id = part.id orelse "";
            if (id.len > 0) call.id = id;

            const name = part.function.name orelse "";
            if (name.len > 0) call.name = name;

            try call.arguments.appendSlice(arena, part.function.arguments orelse "");
        }
    }

    const tool_calls = try arena.alloc(ToolCall, calls.items.len);

    for (tool_calls, calls.items) |*tool_call, call| {
        const arguments = call.arguments.items;

        tool_call.* = .{
            .id = call.id,
            .function = .{
                .name = call.name,
                .arguments = if (arguments.len > 0) arguments else "{}",
            },
        };
    }

    return .{
        .role = .assistant,
        .content = content.written(),
        .tool_calls = if (tool_calls.len > 0) tool_calls else null,
    };
}

fn eventData(line: []const u8) ?[]const u8 {
    const prefix = "data:";
    if (!std.mem.startsWith(u8, line, prefix)) return null;

    return std.mem.trim(u8, line[prefix.len..], " \r");
}

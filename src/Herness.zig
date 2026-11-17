const std = @import("std");
const Io = std.Io;
const Context = @import("Context.zig");
const Event = @import("provider.zig").Event;
const Message = @import("provider.zig").Message;
const Provider = @import("provider.zig").Provider;
const ProviderConfig = @import("provider.zig").Config;
const tool = @import("tool.zig");
const Herness = @This();

const max_tool_rounds = 32;

const system_prompt =
    \\Paths in tool arguments are relative to the current working directory.
;

process: std.process.Init,
provider: ProviderConfig,

pub fn start(herness: Herness) !void {
    const process = herness.process;
    const arena = process.arena.allocator();

    var out_buffer: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writer(process.io, &out_buffer);

    var in_buffer: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().reader(process.io, &in_buffer);

    var client: std.http.Client = .{
        .allocator = process.gpa,
        .io = process.io,
    };
    defer client.deinit();

    const context: Context = .{
        .io = process.io,
        .arena = arena,
        .client = &client,
    };

    const terminal: Terminal = .{
        .out = &stdout.interface,
        .in = &stdin.interface,
    };

    var provider = try Provider.init(
        herness.provider,
        arena,
        process.environ_map,
    );
    defer provider.stop(context);

    provider.connect(context) catch |err| return terminal.report(err);

    try chat(context, terminal, &provider);
}

fn chat(context: Context, terminal: Terminal, provider: *Provider) !void {
    const arena = context.arena;

    var messages: std.ArrayList(Message) = .empty;
    try messages.append(arena, .{ .role = .system, .content = system_prompt });

    while (terminal.readLine("> ")) |line| {
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, "/exit")) break;

        if (std.mem.startsWith(u8, line, "/")) {
            runCommand(context, provider, line[1..]) catch |err|
                terminal.report(err);
            continue;
        }

        const owned_line = try arena.dupe(u8, line);
        try messages.append(arena, .{ .role = .user, .content = owned_line });

        runTurn(
            context,
            terminal,
            provider,
            &messages,
        ) catch |err| terminal.report(err);
    }
}

/// Passes "/name args" to the provider, which defines its own commands.
fn runCommand(context: Context, provider: *Provider, line: []const u8) !void {
    const separator = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
    const name = line[0..separator];
    const args = std.mem.trim(u8, line[separator..], " ");

    try provider.command(context, name, args);
}

/// Runs model turns until the model answers without calling tools.
fn runTurn(
    context: Context,
    terminal: Terminal,
    provider: *Provider,
    messages: *std.ArrayList(Message),
) !void {
    const arena = context.arena;

    for (0..max_tool_rounds) |_| {
        terminal.print("\n", .{});

        const message = try provider.complete(
            context,
            messages.items,
            &tool.definitions,
            terminal,
        );
        try messages.append(arena, message);

        if (message.content.len > 0) terminal.print("\n\n", .{});

        const tool_calls = message.tool_calls orelse return;

        for (tool_calls) |call| {
            const function = call.function;
            const result = runTool(
                context,
                terminal,
                function.name,
                function.arguments,
            ) catch |err|
                try std.fmt.allocPrint(arena, "error: {s}", .{@errorName(err)});

            try messages.append(arena, .{
                .role = .tool,
                .content = result,
                .tool_call_id = call.id,
            });
        }
    }

    terminal.print("stopped: too many tool rounds\n", .{});
}

fn runTool(
    context: Context,
    terminal: Terminal,
    name: []const u8,
    arguments_json: []const u8,
) ![]const u8 {
    const arena = context.arena;
    const call = try tool.parse(arena, name, arguments_json);

    terminal.print("[{s}] {s}\n", .{ @tagName(call), try tool.summary(arena, call) });

    if (tool.needsApproval(call) and !terminal.confirm("allow? [y/N] ")) {
        return error.DeniedByUser;
    }

    return tool.run(context, call, terminal);
}

const Terminal = struct {
    out: *Io.Writer,
    in: *Io.Reader,

    pub fn onEvent(terminal: Terminal, event: Event) void {
        switch (event) {
            .thinking => terminal.print("\x1b[2mthinking...\x1b[0m\n\n", .{}),
            .text => |text| terminal.print("{s}", .{text}),
        }
    }

    pub fn ask(
        terminal: Terminal,
        arena: std.mem.Allocator,
        question: []const u8,
    ) ![]const u8 {
        _ = question;
        const answer = terminal.readLine("answer: ") orelse return error.NoAnswer;
        return arena.dupe(u8, answer);
    }

    fn report(terminal: Terminal, err: anyerror) void {
        terminal.print("error: {s}\n", .{@errorName(err)});
    }

    fn print(terminal: Terminal, comptime fmt: []const u8, args: anytype) void {
        terminal.out.print(fmt, args) catch {};
        terminal.out.flush() catch {};
    }

    fn readLine(terminal: Terminal, prompt: []const u8) ?[]const u8 {
        terminal.print("{s}", .{prompt});
        const line = terminal.in.takeDelimiter('\n') catch return null;
        return std.mem.trimEnd(u8, line orelse return null, "\r");
    }

    fn confirm(terminal: Terminal, question: []const u8) bool {
        const answer = terminal.readLine(question) orelse return false;
        return std.mem.eql(u8, std.mem.trim(u8, answer, " "), "y");
    }
};

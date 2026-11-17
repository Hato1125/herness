const std = @import("std");
const llm = @import("llm.zig");
const Context = @import("Context.zig");
const Llama = @import("providers/Llama.zig");
const Ollama = @import("providers/Ollama.zig");
const Claude = @import("providers/Claude.zig");
const Gemini = @import("providers/Gemini.zig");

pub const Message = llm.Message;

pub const Event = union(enum) {
    thinking,
    text: []const u8,
    tool: []const u8,
};

pub const Approval = struct {
    title: []const u8,
};

pub const Kind = enum {
    llama,
    ollama,
    claude,
    gemini,
};

pub const Config = union(Kind) {
    llama: Llama.Config,
    ollama: Ollama.Config,
    claude: Claude.Config,
    gemini: Gemini.Config,
};

pub const Provider = union(Kind) {
    llama: Llama,
    ollama: Ollama,
    claude: Claude,
    gemini: Gemini,

    pub fn init(
        config: Config,
        arena: std.mem.Allocator,
        env: *const std.process.Environ.Map,
    ) !Provider {
        return switch (config) {
            inline else => |provider_config, kind| @unionInit(
                Provider,
                @tagName(kind),
                try @FieldType(Provider, @tagName(kind)).init(
                    arena,
                    env,
                    provider_config,
                ),
            ),
        };
    }

    pub fn connect(provider: *Provider, context: Context) !void {
        return switch (provider.*) {
            inline else => |*self| self.connect(context),
        };
    }

    pub fn complete(
        provider: *Provider,
        context: Context,
        messages: []const Message,
        tools: []const llm.Tool,
        listener: anytype,
    ) !Message {
        return switch (provider.*) {
            inline else => |*self| self.complete(
                context,
                messages,
                tools,
                listener,
            ),
        };
    }

    pub fn command(
        provider: *Provider,
        context: Context,
        command_name: []const u8,
        args: []const u8,
    ) !void {
        switch (provider.*) {
            inline else => |*self| {
                const commands = @TypeOf(self.*).commands;

                inline for (@typeInfo(commands).@"struct".decl_names) |declared| {
                    if (std.mem.eql(u8, command_name, declared)) {
                        return @field(
                            commands,
                            declared,
                        ).run(self, context, args);
                    }
                }

                return error.UnknownCommand;
            },
        }
    }

    pub fn name(provider: *const Provider) []const u8 {
        return switch (provider.*) {
            inline else => |self| @TypeOf(self).name,
        };
    }

    pub fn icon(provider: *const Provider) []const u8 {
        return switch (provider.*) {
            inline else => |self| @TypeOf(self).icon,
        };
    }

    pub fn stop(provider: *Provider, context: Context) void {
        switch (provider.*) {
            inline else => |*self| self.stop(context),
        }
    }
};

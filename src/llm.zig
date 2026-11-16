pub const Role = enum {
    system,
    user,
    assistant,
    tool,
};

pub const Message = struct {
    role: Role,
    content: []const u8 = "",
    tool_calls: ?[]const ToolCall = null,
    tool_call_id: ?[]const u8 = null,
};

pub const ToolCall = struct {
    id: []const u8 = "",
    type: []const u8 = "function",
    function: Function,

    pub const Function = struct {
        name: []const u8,
        arguments: []const u8 = "{}",
    };
};

pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    parameters: []const u8,
};

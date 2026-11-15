const std = @import("std");

io: std.Io,
arena: std.mem.Allocator,
client: *std.http.Client,

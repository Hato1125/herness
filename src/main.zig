const std = @import("std");
const Herness = @import("Herness.zig");

pub fn main(init: std.process.Init) !void {
    try (Herness{
        .process = init,
        .provider = .llama,
    }).start();
}

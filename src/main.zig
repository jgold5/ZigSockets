const std = @import("std");
const thread = std.Thread;
const root = @import("root.zig");

pub fn main() !void {
    const t_serve = try thread.spawn(.{}, root.startServer, .{ "127.0.0.1", 8000 });
    t_serve.join();
}

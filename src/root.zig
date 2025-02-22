const std = @import("std");
const testing = std.testing;
const server = @import("server.zig");
const client = @import("client.zig");

pub fn startServer(name: []const u8, port: u16) !void {
    try server.startServer(name, port);
}

pub fn connect(name: []const u8, port: u16) !void {
    try client.connect(name, port);
}

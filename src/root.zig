const std = @import("std");
const testing = std.testing;
const server = @import("server.zig");
const client = @import("client.zig");

pub fn start_server(name: []const u8, port: u16) !void {
    try server.start_server(name, port);
}

pub fn connect(name: []const u8, port: u16) !void {
    try client.connect(name, port);
}

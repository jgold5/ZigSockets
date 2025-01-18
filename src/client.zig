const std = @import("std");
const net = std.net;

pub fn connect(name: []const u8, port: u16) !void {
    const addr: net.Address = try net.Address.parseIp4(name, port);
    const stream: net.Stream = try net.tcpConnectToAddress(addr);
    defer stream.close();
    const request = "GET / HTTP/1.1\nHost: http://localhost\nAccept: */*\nConnection: keep-alive";
    _ = try stream.write(request);
}

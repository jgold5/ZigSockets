const std = @import("std");
const net = std.net;

pub fn main() !void {
    const name = "127.0.0.1";
    const port = 8000;
    const addr: net.Address = try net.Address.parseIp4(name, port);
    const stream: net.Stream = try net.tcpConnectToAddress(addr);
    defer stream.close();
    const request =
        \\GET / HTTP/1.1
        \\host: localhost:8000
        \\connection: upgrade
        \\upgrade: websocket
        \\sec-websocket-key: dGhlIHNhbXBsZSBub25jZQ==
        \\sec-websocket-version: 13
        \\sec-websocket-extensions: permessage-deflate; client_max_window_bits
        \\accept: */*
        \\accept-language: *
        \\sec-fetch-mode: websocket
        \\user-agent: node
        \\pragma: no-cache
        \\cache-control: no-cache
        \\accept-encoding: gzip, deflate"
    ;
    _ = try stream.write(request);
}

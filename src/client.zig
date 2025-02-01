const std = @import("std");
const net = std.net;

pub fn main() !void {
    const name = "127.0.0.1";
    const port = 8000;
    const addr: net.Address = try net.Address.parseIp4(name, port);
    const stream: net.Stream = try net.tcpConnectToAddress(addr);
    defer stream.close();
    const request =
        "GET / HTTP/1.1\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "Sec-WebSocket-Key: mjjHW1OGSoglSszFCMuOUQ==\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits\r\n" ++
        "Host: 127.0.0.1:8000\r\n" ++
        "\r\n";
    _ = try stream.write(request);
}

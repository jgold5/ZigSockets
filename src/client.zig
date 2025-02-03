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

const Opcode = enum(u4) {
    cont = 0x0,
    txt = 0x1,
    bin = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xa,
};

const Frame = struct {
    fin: u1,
    opcode: Opcode,
    //mask: u1,
    //payload_len: [9]u8,
    //mask_key: ?u32,
    //payload: []u8,

    pub fn toBits(self: Frame) u8 {
        return @as(u8, self.fin) << 7 | @as(u8, @intFromEnum(self.opcode));
    }
};

const pl: []const u8 = "HIHIHIHIHIHIHIHI";
const mk = [_]u8{ 0x5b, 0x61, 0xf2, 0xf8 };
const p_len = pl.len;
const fin: u1 = 1;

pub fn mask_payload(alloc: std.mem.Allocator, payload: []const u8, mask_key: [4]u8) ![]u8 {
    var masked_payload = try alloc.alloc(u8, payload.len);
    for (payload, 0..) |char, i| {
        masked_payload[i] = char ^ mask_key[i % mask_key.len];
    }
    return masked_payload;
}

test "rand" {
    const alloc = std.testing.allocator;
    const masked_payload = try mask_payload(alloc, pl, mk);
    defer alloc.free(masked_payload);
    std.debug.print("{x}", .{masked_payload});
    const a = Frame{ .fin = 1, .opcode = Opcode.ping };
    std.debug.print("{x}", .{a.toBits()});
}

//{ 81, 90, 5b, 61, f2, f8, 13, 28, ba, b1, 13, 28, ba, b1, 13, 28, ba, b1, 13, 28, ba, b1 }
//
// 81: 1000 0001: FINAL + Text OP
// 90: 1001 0000: Mask - 1, Payload length - 16 bytes
// 5b 61 f2 f8 - Masking Key
// Rest: Payload
//
// 0x48 XOR 0x5B
// 0100 1000
// 0101 1011
// 0001 0011 = 13
//
// 0100 1001
// 0110 0001
// 0010 1000 = 28

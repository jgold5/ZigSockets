const std = @import("std");
const base64 = std.base64;
const sha1 = std.crypto.hash.Sha1;
const net = std.net;
const fmt = std.fmt;
const gpa = std.heap.GeneralPurposeAllocator;
const gpaConfig = std.heap.GeneralPurposeAllocatorConfig;
const arrayList = std.ArrayList;
const default_config = gpaConfig{};
const chunk_size: usize = 1024;
const guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

const Request = struct {
    method: []u8,
    uri: []u8,
    protocol: []u8,

    pub fn print_uri(self: Request) void {
        std.debug.print("uri: {s}\n", .{self.uri});
    }
};

pub fn start_server(name: []const u8, port: u16) !void {
    const addr = try net.Address.parseIp4(name, port);
    var server = try net.Address.listen(addr, .{});
    defer server.deinit();
    var initializedGpa = gpa(default_config){};
    const alloc = initializedGpa.allocator();
    defer _ = initializedGpa.deinit();
    while (true) {
        try handle_conn(alloc, &server);
        std.debug.print("DISCONNECTED\n", .{});
    }
}

fn handle_conn(allocator: std.mem.Allocator, server: *net.Server) !void {
    const conn = try server.accept();
    std.debug.print("CONNECTED\n", .{});
    const stream = conn.stream;
    defer stream.close();
    var read_buf = try allocator.alloc(u8, chunk_size);
    var msg_buf = try allocator.alloc(u8, chunk_size);
    defer allocator.free(read_buf);
    defer allocator.free(msg_buf);
    const bytes_read = try stream.read(read_buf);
    if (bytes_read == 0) {
        return;
    }
    const req: []u8 = read_buf[0..bytes_read];
    std.debug.print("Req:\n{s}\n", .{req});
    try send_response(allocator, stream, req);
    const msg_b = try stream.read(msg_buf);
    std.debug.print("Req:\n{x}\n", .{msg_buf[0..msg_b]});
}

fn send_response(allocator: std.mem.Allocator, stream: net.Stream, req: []const u8) !void {
    const req_line = try chop_newline(req, 0); //request line
    const version_line = try chop_newline(req, req_line.?); //host
    const key_line = try chop_newline(req, version_line.?); //key
    const field_and_key = req[version_line.? .. key_line.? - 2];
    const field = try chop_space(field_and_key, 0);
    const accept = try compute_ws_accept(allocator, field_and_key[field.?..]);
    defer allocator.free(accept);
    const response =
        "HTTP/1.1 101 Switching Protocols\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Accept: {s}\r\n" ++
        "\r\n";
    const resp = try std.fmt.allocPrint(allocator, response, .{accept});
    defer allocator.free(resp);
    _ = try stream.write(resp);
    std.debug.print("Resp:\n{s}\n", .{resp});
}

fn handle_req_line(req_line: []u8) !void {
    const method = try chop_space(req_line);
    const uri = try chop_space(req_line);
    const protocol = try chop_space(req_line);
    const r: Request = Request{ .method = method, .uri = uri, .protocol = protocol };
    _ = &r;
}

fn chop_newline(req: []const u8, from: usize) !?usize {
    if (from > req.len) {
        return error.OutOfBounds;
    }
    const ind = std.mem.indexOf(u8, req[from..], "\r\n");
    if (ind != null) {
        return from + ind.? + 2;
    } else {
        return null;
    }
}

fn chop_space(req: []const u8, from: usize) !?usize {
    if (from > req.len) {
        return error.OutOfBounds;
    }
    const ind = std.mem.indexOf(u8, req[from..], " ");
    if (ind != null) {
        return from + ind.? + 1;
    } else {
        return null;
    }
}

fn compute_ws_accept(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    var dest_sha: [20]u8 = undefined;
    const as_slice = try std.mem.concat(allocator, u8, &[_][]const u8{ key, guid });
    sha1.hash(as_slice, &dest_sha, .{});
    allocator.free(as_slice);
    const ac: []const u8 = &dest_sha;
    const encoder = base64.Base64Encoder.init(base64.standard_alphabet_chars, '=');
    const size = encoder.calcSize(20);
    const dst_buf = try allocator.alloc(u8, size);
    return encoder.encode(dst_buf, ac);
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
    fin: u8,
    opcode: Opcode,
    mask_key: [4]u8,
    payload: []const u8,

    pub fn init(payload: []const u8) Frame {
        const self = Frame{
            .fin = 1,
            .payload = payload,
            .mask_key = generate_mask_key(),
            .opcode = Opcode.txt,
        };
        return self;
    }

    fn generate_mask_key() [4]u8 {
        return [_]u8{ 0x5b, 0x61, 0xf2, 0xf8 };
    }

    pub fn gen_frame_bits(self: Frame, alloc: std.mem.Allocator) ![]u8 {
        var list = std.ArrayList(u8).init(alloc);
        defer list.deinit();
        const payload_len: u8 = @intCast(self.payload.len);
        try list.append(@as(u8, self.fin) << 7 | @as(u8, @intFromEnum(self.opcode)));
        try list.append(1 << 7 | payload_len);
        try list.appendSlice(&self.mask_key);
        const masked_payload = try self.mask_payload(alloc);
        defer alloc.free(masked_payload);
        try list.appendSlice(masked_payload);
        return list.toOwnedSlice();
    }

    pub fn mask_payload(self: Frame, alloc: std.mem.Allocator) ![]u8 {
        var masked_payload = try alloc.alloc(u8, self.payload.len);
        for (self.payload, 0..) |char, i| {
            masked_payload[i] = char ^ self.mask_key[i % self.mask_key.len];
        }
        return masked_payload;
    }
};

fn unmask_message(alloc: std.mem.Allocator, message: []const u8) !void {
    const first = message[0];
    const next = message[1];
    const mask = message[2..6];
    const payload = message[6..];
    const fin = (message[0] >> 7) & 0b1});
    const opcode = message[0] & 0b1111;
    std.debug.print("{x}\n", .{(next >> 7) & 0b1});
    std.debug.print("{x}\n", .{(next) & 0b1111111});
    std.debug.print("{x}\n", .{mask});
    std.debug.print("{x}\n", .{payload});
    const unmasked = try unmask_payload(payload, mask, alloc);
    defer alloc.free(unmasked);
    std.debug.print("{s}\n", .{unmasked});
}

pub fn unmask_payload(payload: []const u8, mask_key: []const u8, alloc: std.mem.Allocator) ![]u8 {
    var masked_payload = try alloc.alloc(u8, payload.len);
    for (payload, 0..) |char, i| {
        masked_payload[i] = char ^ mask_key[i % mask_key.len];
    }
    return masked_payload;
}

test "unmask" {
    const alloc = std.testing.allocator;
    const msg = [_]u8{ 0x81, 0x90, 0x5b, 0x61, 0xf2, 0xf8, 0x13, 0x28, 0xba, 0xb1, 0x13, 0x28, 0xba, 0xb1, 0x13, 0x28, 0xba, 0xb1, 0x13, 0x28, 0xba, 0xb1 };
    const a: []const u8 = &msg;
    try unmask_message(alloc, a);
}

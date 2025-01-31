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
        std.debug.print("\nDisconnected\n", .{});
    }
}

fn handle_conn(allocator: std.mem.Allocator, server: *net.Server) !void {
    const conn = try server.accept();
    std.debug.print("Connected\n", .{});
    const stream = conn.stream;
    defer stream.close();
    var read_buf = try allocator.alloc(u8, chunk_size);
    defer allocator.free(read_buf);
    const bytes_read = try stream.read(read_buf);
    if (bytes_read == 0) {
        return;
    }
    var req: []u8 = read_buf[0..bytes_read];
    std.debug.print("{s}", .{req});
    _ = try chop_newline(&req); //request line
    _ = try chop_newline(&req); //host
    _ = try chop_newline(&req); //connection
    _ = try chop_newline(&req); //upgrade
    var key = try chop_newline(&req); //key
    try send_response(allocator, stream, &key);
}

fn send_response(allocator: std.mem.Allocator, stream: net.Stream, key_line: *[]u8) !void {
    const accept = try handle_key_line(allocator, key_line);
    defer allocator.free(accept);
    const response =
        \\HTTP/1.1 101 Switching Protocols
        \\Upgrade: websocket
        \\Connection: Upgrade
        \\Sec-WebSocket-Accept: {s}
    ;
    const resp = try std.fmt.allocPrint(allocator, response, .{accept});
    defer allocator.free(resp);
    _ = try stream.write(resp);
    std.debug.print("{s}", .{resp});
}

fn handle_key_line(allocator: std.mem.Allocator, key_line: *[]u8) ![]const u8 {
    _ = try chop_space(key_line);
    const key = try chop_space(key_line);
    return try compute_ws_accept(allocator, key);
}

fn handle_req_line(req_line: *[]u8) !void {
    const method = try chop_space(req_line);
    const uri = try chop_space(req_line);
    const protocol = try chop_space(req_line);
    const r: Request = Request{ .method = method, .uri = uri, .protocol = protocol };
    _ = &r;
}

fn chop_newline(req: *[]u8) ![]u8 {
    const index = std.mem.indexOf(u8, req.*, "\r\n") orelse return req.*;
    const res = req.*[0..index];
    req.* = req.*[index + 2 .. req.len];
    return res;
}

fn chop_space(req: *[]u8) ![]u8 {
    const index = std.mem.indexOf(u8, req.*, " ") orelse return req.*;
    const res = req.*[0..index];
    req.* = req.*[index + 1 .. req.len];
    return res;
}

fn compute_ws_accept(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    var dest_sha: [20]u8 = undefined;
    const as_slice = try std.mem.concat(allocator, u8, &[_][]const u8{ key, guid });
    sha1.hash(as_slice, &dest_sha, .{});
    const ac: []const u8 = &dest_sha;
    const encoder = base64.Base64Encoder.init(base64.standard_alphabet_chars, '=');
    const size = encoder.calcSize(20);
    const dst_buf = try allocator.alloc(u8, size);
    return encoder.encode(dst_buf, ac);
}

test "cp" {
    const alloc = std.testing.allocator;
    const key = "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==";
    var a = try std.mem.concat(alloc, u8, &[_][]const u8{ key, "" });
    const res = try handle_key_line(alloc, &a);
    defer alloc.free(res);
    std.debug.print("{s}", .{res});
}

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
    const req: []u8 = read_buf[0..bytes_read];
    std.debug.print("Req:\n{s}\n", .{req});
    const req_line = try chop_newline(req, 0); //request line
    const version_line = try chop_newline(req, req_line.?); //host
    const key_line = try chop_newline(req, version_line.?); //key
    try send_response(allocator, stream, req[version_line.? .. key_line.? - 2]);
}

fn send_response(allocator: std.mem.Allocator, stream: net.Stream, key_line: []const u8) !void {
    const accept = try handle_key_line(allocator, key_line);
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

fn handle_key_line(allocator: std.mem.Allocator, key_line: []const u8) ![]const u8 {
    const field = try chop_space(key_line, 0);
    std.debug.print("Calculating for: {s}:\n", .{key_line[field.?..]});
    return try compute_ws_accept(allocator, key_line[field.?..]);
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

test "cp" {
    const alloc = std.testing.allocator;
    const key = "Sec-WebSocket-Key: wNqq4Bq6yXtfuveIu96IjQ==";
    const res = try handle_key_line(alloc, key);
    defer alloc.free(res);
    std.debug.print("{s}", .{res});
}

const std = @import("std");
const base64 = std.base64;
const net = std.net;
const gpa = std.heap.GeneralPurposeAllocator;
const gpaConfig = std.heap.GeneralPurposeAllocatorConfig;
var initializedGpa = gpa(default_config){};
const alloc = initializedGpa.allocator();
const arrayList = std.ArrayList;
const default_config = gpaConfig{};
const chunk_size: usize = 1024;

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
    while (true) {
        try handle_conn(&server);
        std.debug.print("Disconnected\n", .{});
    }
}

fn handle_conn(server: *net.Server) !void {
    const conn = try server.accept();
    std.debug.print("Connected\n", .{});
    const stream = conn.stream;
    defer stream.close();
    var read_buf = try alloc.alloc(u8, chunk_size);
    defer alloc.free(read_buf);
    const write_buf = try alloc.alloc(u8, chunk_size);
    defer alloc.free(write_buf);
    const bytes_read = try stream.read(read_buf);
    if (bytes_read == 0) {
        return;
    }
    var req: []u8 = read_buf[0..bytes_read];
    std.debug.print("{s}", .{req});
    var req_line = try chop_newline(&req);
    try handle_req_line(&req_line);
}

fn handle_req_line(req_line: *[]u8) !void {
    const method = try chop_space(req_line);
    const uri = try chop_space(req_line);
    const protocol = try chop_space(req_line);
    const r: Request = Request{ .method = method, .uri = uri, .protocol = protocol };
    r.print_uri();
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

test "make_accept" {
    const decoder = base64.Base64Decoder.init(base64.standard_alphabet_chars, '=');
    const src = "dbH/OKmdMCxS3CaXIQYKlA==";
    const size = try decoder.calcSizeForSlice(src);
    const dst_buf = try alloc.alloc(u8, size);
    defer alloc.free(dst_buf);
    _ = try decoder.decode(dst_buf, src);
    std.debug.print("{s}", .{dst_buf});
}

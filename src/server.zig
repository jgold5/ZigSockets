const std = @import("std");
const base64 = std.base64;
const sha1 = std.crypto.hash.Sha1;
const linux = std.os.linux;
const net = std.net;
const fmt = std.fmt;
const gpa = std.heap.GeneralPurposeAllocator;
const gpaConfig = std.heap.GeneralPurposeAllocatorConfig;
const arrayList = std.ArrayList;
const default_config = gpaConfig{};
const chunk_size: usize = 1024;
const guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const max_wait = 1_000_000_000;

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
    defer allocator.free(read_buf);
    const bytes_read = try stream.read(read_buf);
    if (bytes_read == 0) {
        return;
    }
    const req: []u8 = read_buf[0..bytes_read];
    std.debug.print("Req:\n{s}\n", .{req});
    try send_response(allocator, stream, req);
    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (true) {
        const msg_buf = try allocator.alloc(u8, chunk_size);
        const msg_b = try stream.read(msg_buf[i..]);
        const curr_msg = msg_buf[i .. i + msg_b];
        if (msg_b > 0) {
            const opcode = get_opcode(curr_msg);
            if (opcode == .close) {
                std.debug.print("Closing\n", .{});
                break;
            } else if (opcode == .txt) {
                try unmask_message(allocator, curr_msg);
                i += msg_b;
                timer.reset();
            }
        }
        const curr_time = timer.read();
        if (curr_time > max_wait) {
            break;
        }
    }
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

fn unmask_message(alloc: std.mem.Allocator, message: []const u8) !void {
    const payload_len = get_payload_len(message);
    var start_mask: usize = 0;
    if (payload_len < 126) {
        start_mask = 2;
    } else {
        start_mask = 4;
    }
    const end_mask = start_mask + 4;
    const mask = message[start_mask..end_mask];
    const payload = message[end_mask..];
    //   const fin = (message[0] >> 7) & 0b1;
    const opcode = message[0] & 0b1111;
    const unmasked = try unmask_payload(alloc, payload, mask);
    defer alloc.free(unmasked);
    std.debug.print("OG Message: {x}\n", .{message});
    std.debug.print("Opcode: {x}\n", .{opcode});
    std.debug.print("Unmasked: {s}\n", .{unmasked});
}

fn get_opcode(message: []const u8) Opcode {
    const opcode = message[0] & 0b1111;
    return @enumFromInt(opcode);
}

fn get_payload_len(message: []const u8) usize {
    const len: u8 = message[1] & 0b1111111;
    if (len < 126) {
        return len;
    } else {
        return message[2] << 4 | message[3];
    }
}

pub fn unmask_payload(alloc: std.mem.Allocator, payload: []const u8, mask_key: []const u8) ![]u8 {
    var masked_payload = try alloc.alloc(u8, payload.len);
    for (payload, 0..) |char, i| {
        masked_payload[i] = char ^ mask_key[i % mask_key.len];
    }
    return masked_payload;
}

test "epoll" {
    const alloc = std.testing.allocator;
    const addr = try net.Address.parseIp4("127.0.0.1", 8000);
    var server = try net.Address.listen(addr, .{ .force_nonblocking = true });
    defer server.deinit();
    var server_ev = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = server.stream.handle } };
    const epfd: i32 = @intCast(linux.epoll_create());
    const reg = linux.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, server.stream.handle, &server_ev);
    if (reg < 0) {
        return error.Epoll_ctl_unsuccessful;
    }
    var events: [10]linux.epoll_event = undefined;
    var streams: [10]net.Stream = undefined;
    var i: usize = 0;
    while (true) {
        const nfds = linux.epoll_wait(epfd, &events, 10, -1);
        if (nfds > 0) {
            std.debug.print("NFDS {}\n", .{nfds});
        }
        for (events[0..nfds]) |ev| {
            if (ev.data.fd == server.stream.handle) {
                std.debug.print("Connecting \n", .{});
                const conn = try server.accept();
                const stream = conn.stream;
                streams[i] = stream;
                i += 1;
                std.debug.print("Handle: {}\n", .{stream.handle});
                var client_ev = linux.epoll_event{ .events = linux.EPOLL.IN | linux.EPOLL.ET, .data = .{ .fd = stream.handle } };
                _ = linux.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, stream.handle, &client_ev);
            } else {
                var read_buf = try alloc.alloc(u8, chunk_size);
                defer alloc.free(read_buf);
                const read = try streams[i - 1].read(read_buf);
                std.debug.print("READ: {s}\n", .{read_buf[0..read]});
            }
        }

        //var ev = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = stream.handle } };
        //_ = linux.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, stream.handle, &ev);
        //std.debug.print("Handle: {}\n", .{stream.handle});
    }
    std.debug.print("Handle: {}\n", .{server.stream.handle});
    std.debug.print("EPFD {}\n", .{epfd});
}

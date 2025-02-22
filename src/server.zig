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
const CHUNK_SIZE: usize = 1024;
const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const MAX_WAIT = 1_000_000_000;

const ConnectionState = struct {
    stream: net.Stream,
    readQueue: std.ArrayList([]const u8),
    writeQueue: std.ArrayList([]const u8),
    connected: bool,

    pub fn init(stream: net.Stream, allocator: std.mem.Allocator) ConnectionState {
        return ConnectionState{
            .stream = stream,
            .readQueue = std.ArrayList([]const u8).init(allocator),
            .writeQueue = std.ArrayList([]const u8).init(allocator),
            .connected = false,
        };
    }

    pub fn deinit(self: *ConnectionState) void {
        self.readQueue.deinit();
        self.writeQueue.deinit();
        self.stream.close();
    }

    pub fn register(self: ConnectionState, epfd: i32) void {
        var client_ev = linux.epoll_event{ .events = linux.EPOLL.IN | linux.EPOLL.ET, .data = .{ .fd = self.stream.handle } };
        _ = linux.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, self.stream.handle, &client_ev);
    }

    pub fn getConnected(self: ConnectionState) bool {
        return self.connected;
    }

    pub fn setConnected(self: *ConnectionState, state: bool) void {
        self.connected = state;
    }
};

pub fn startServer(name: []const u8, port: u16) !void {
    const addr = try net.Address.parseIp4(name, port);
    var server = try net.Address.listen(addr, .{ .force_nonblocking = true });
    defer server.deinit();
    var server_ev = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = server.stream.handle } };
    const epfd: i32 = @intCast(linux.epoll_create());
    const reg = linux.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, server.stream.handle, &server_ev);
    if (reg < 0) {
        return error.Epoll_ctl_unsuccessful;
    }
    var initializedGpa = gpa(default_config){};
    const alloc = initializedGpa.allocator();
    defer _ = initializedGpa.deinit();
    var connectionMap = std.AutoHashMap(i32, *ConnectionState).init(alloc);
    var events: [10]linux.epoll_event = undefined;
    while (true) {
        const nfds = linux.epoll_wait(epfd, &events, 10, -1);
        for (events[0..nfds]) |ev| {
            if (ev.data.fd == server.stream.handle) {
                try registerConnection(&connectionMap, epfd, alloc, &server);
            } else {
                const curr_conn = connectionMap.get(ev.data.fd).?;
                if (!curr_conn.getConnected()) {
                    try acceptHandshake(&connectionMap, ev.data.fd, alloc);
                } else {
                    try manageConnection(&connectionMap, ev.data.fd, alloc);
                }
            }
        }
    }
    connectionMap.deinit();
}

fn registerConnection(map: *std.AutoHashMap(i32, *ConnectionState), epfd: i32, allocator: std.mem.Allocator, server: *net.Server) !void {
    const conn = try server.accept();
    std.debug.print("CONNECTED\n", .{});
    var connection = try allocator.create(ConnectionState);
    connection.* = ConnectionState.init(conn.stream, allocator);
    connection.register(epfd);
    try map.put(conn.stream.handle, connection);
}

fn closeConnection(map: *std.AutoHashMap(i32, *ConnectionState), connection_fd: i32) !void {
    var connection = map.get(connection_fd).?;
    connection.deinit();
    _ = map.remove(connection_fd);
}

fn acceptHandshake(map: *std.AutoHashMap(i32, *ConnectionState), connection_fd: i32, allocator: std.mem.Allocator) !void {
    var connection = map.get(connection_fd).?;
    const read_buf = try allocator.alloc(u8, CHUNK_SIZE);
    defer allocator.free(read_buf);
    const bytes_read = try connection.stream.read(read_buf);
    if (bytes_read == 0) {
        return;
    }
    const req: []u8 = read_buf[0..bytes_read];
    std.debug.print("Req:\n{s}\n", .{req});
    try sendResponse(allocator, connection.stream, req);
    connection.setConnected(true);
}

fn manageConnection(map: *std.AutoHashMap(i32, *ConnectionState), connection_fd: i32, allocator: std.mem.Allocator) !void {
    var i: usize = 0;
    var connection = map.get(connection_fd).?;
    const msg_buf = try allocator.alloc(u8, CHUNK_SIZE);
    const msg_b = try connection.stream.read(msg_buf[i..]);
    const curr_msg = msg_buf[i .. i + msg_b];
    const opcode = getOpcode(curr_msg);
    if (opcode == .close) {
        std.debug.print("Closing\n", .{});
        try closeConnection(map, connection_fd);
    } else if (opcode == .txt) {
        try unmaskMessage(allocator, curr_msg);
        i += msg_b;
    }
}

fn sendResponse(allocator: std.mem.Allocator, stream: net.Stream, req: []const u8) !void {
    const req_line = try chopNewline(req, 0); //request line
    const version_line = try chopNewline(req, req_line.?); //host
    const key_line = try chopNewline(req, version_line.?); //key
    const field_and_key = req[version_line.? .. key_line.? - 2];
    const field = try chopSpace(field_and_key, 0);
    const accept = try computeWSAccept(allocator, field_and_key[field.?..]);
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

fn chopNewline(req: []const u8, from: usize) !?usize {
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

fn chopSpace(req: []const u8, from: usize) !?usize {
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

fn computeWSAccept(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    var dest_sha: [20]u8 = undefined;
    const as_slice = try std.mem.concat(allocator, u8, &[_][]const u8{ key, GUID });
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

fn unmaskMessage(alloc: std.mem.Allocator, message: []const u8) !void {
    const payload_len = getPayloadLen(message);
    var start_mask: usize = 0;
    if (payload_len < 126) {
        start_mask = 2;
    } else {
        start_mask = 4;
    }
    const end_mask = start_mask + 4;
    const mask = message[start_mask..end_mask];
    const payload = message[end_mask..];
    const opcode = message[0] & 0b1111;
    const unmasked = try unmaskPayload(alloc, payload, mask);
    defer alloc.free(unmasked);
    std.debug.print("OG Message: {x}\n", .{message});
    std.debug.print("Opcode: {x}\n", .{opcode});
    std.debug.print("Unmasked: {s}\n", .{unmasked});
}

fn getOpcode(message: []const u8) Opcode {
    const opcode = message[0] & 0b1111;
    return @enumFromInt(opcode);
}

fn getPayloadLen(message: []const u8) usize {
    const len: u8 = message[1] & 0b1111111;
    if (len < 126) {
        return len;
    } else {
        return message[2] << 4 | message[3];
    }
}

pub fn unmaskPayload(alloc: std.mem.Allocator, payload: []const u8, mask_key: []const u8) ![]u8 {
    var masked_payload = try alloc.alloc(u8, payload.len);
    for (payload, 0..) |char, i| {
        masked_payload[i] = char ^ mask_key[i % mask_key.len];
    }
    return masked_payload;
}

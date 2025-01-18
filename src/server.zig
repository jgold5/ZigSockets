const std = @import("std");
const net = std.net;

pub fn start_server(name: []const u8, port: u16) !void {
    while (true) {
        const stream = try open_socket(name, port);
        defer stream.close();
        std.debug.print("Connected\n", .{});
        try handle_conn(stream);
        std.debug.print("Disconnected\n", .{});
    }
}

fn open_socket(name: []const u8, port: u16) !net.Stream {
    const addr = try net.Address.parseIp4(name, port);
    var server = try net.Address.listen(addr, .{});
    defer server.deinit();
    const conn = try server.accept();
    return conn.stream;
}

fn send_response(stream: net.Stream) void {
    _ = stream.write(">") catch |err| switch (err) {
        error.BrokenPipe => {
            return;
        },
        else => |e| {
            std.debug.print("Unexpected error: {}\n", .{e});
        },
    };
}

fn handle_conn(stream: net.Stream) !void {
    const alloc = std.heap.page_allocator;
    const read_buf = try alloc.alloc(u8, 1024);
    const write_buf = try alloc.alloc(u8, 1024);
    while (true) {
        const bytes_read = try stream.read(read_buf);
        if (bytes_read == 0) {
            break;
        }
        const res = try std.fs.cwd().readFile("src/index.html", write_buf);
        std.debug.print("Index: {s}\n", .{res});

        const resp = "HTTP/1.1 200 OK\nContent-Type: application/json\nContent-Length: 30\n\n{\"status\":\"success\",\"data\":{}}\r\n";
        _ = try stream.write(resp);
        //_ = try stream.write(res);
        std.debug.print("Read: {} bytes\n", .{bytes_read});
        std.debug.print("Read: {s}\n", .{read_buf[0..bytes_read]});
    }
}

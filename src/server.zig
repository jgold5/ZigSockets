const std = @import("std");
const net = std.net;
const gpa = std.heap.GeneralPurposeAllocator;
const gpaConfig = std.heap.GeneralPurposeAllocatorConfig;
const arrayList = std.ArrayList;

pub fn start_server(name: []const u8, port: u16) !void {
    const addr = try net.Address.parseIp4(name, port);
    var server = try net.Address.listen(addr, .{});
    defer server.deinit();
    while (true) {
        try handle_conn(&server);
        std.debug.print("Disconnected\n", .{});
    }
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

fn handle_conn(server: *net.Server) !void {
    const conn = try server.accept();
    std.debug.print("Connected\n", .{});
    const stream = conn.stream;
    defer stream.close();
    const default_config = gpaConfig{};
    var initializedGpa = gpa(default_config){};
    const alloc = initializedGpa.allocator();
    const read_buf = try alloc.alloc(u8, 1024);
    const write_buf = try alloc.alloc(u8, 1024);
    var al = arrayList(u8).init(alloc);
    const bytes_read = try stream.read(read_buf);
    if (bytes_read == 0) {
        return;
    }
    const response_header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: ";
    const res = try std.fs.cwd().readFile("src/index.html", write_buf);
    const len_as_str = try std.fmt.allocPrint(alloc, "{d}", .{res.len});
    _ = try al.appendSlice(response_header);
    _ = try al.appendSlice(len_as_str);
    _ = try al.appendSlice("\r\n\r\n");
    _ = try al.appendSlice(res);
    _ = try stream.write(try al.toOwnedSlice());
    std.debug.print("Read: {} bytes\n", .{bytes_read});
    std.debug.print("Read: {s}\n", .{read_buf[0..bytes_read]});
}

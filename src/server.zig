const std = @import("std");
const net = std.net;

pub fn start_server() !void {
    const addr = try net.Address.parseIp4("127.0.0.1", 8000);
    var server = try net.Address.listen(addr, .{});
    defer server.deinit();
    while (true) {
        const conn = try server.accept();
        const stream = conn.stream;
        defer stream.close();
        std.debug.print("Connected\n", .{});
        const alloc = std.heap.page_allocator;
        const buff = try alloc.alloc(u8, 1024);
        const bytes_read = try stream.read(buff);
        std.debug.print("Read: {s}\n", .{buff[0 .. bytes_read - 1]});
        if (bytes_read > 0) {
            const greeting = "Hello there. Welcome to my server!";
            _ = try stream.write(greeting);
        }
    }
}

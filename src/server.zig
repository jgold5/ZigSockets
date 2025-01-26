const std = @import("std");
const net = std.net;
const gpa = std.heap.GeneralPurposeAllocator;
const gpaConfig = std.heap.GeneralPurposeAllocatorConfig;
const arrayList = std.ArrayList;
const default_config = gpaConfig{};
const chunk_size: usize = 1024;

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
    var initializedGpa = gpa(default_config){};
    const alloc = initializedGpa.allocator();
    var read_buf = try alloc.alloc(u8, chunk_size);
    const write_buf = try alloc.alloc(u8, chunk_size);
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
    var req: []u8 = read_buf[0..bytes_read];
    std.debug.print("{s}", .{req});
    var req_line = try chop_newline(&req);
    try handle_req_line(&req_line);
}

fn handle_req_line(req_line: *[]u8) !void {
    const method = try chop_space(req_line);
    const uri = try chop_space(req_line);
    const protocol = try chop_space(req_line);
    std.debug.print("Method {s}\nURI {s}\nProto {s}", .{ method, uri, protocol });
}

fn chop_newline(req: *[]u8) ![]u8 {
    const new_line = "\r\n";
    var i: usize = 0;
    var initializedGpa = gpa(default_config){};
    const alloc = initializedGpa.allocator();
    var curr_chunk = try alloc.alloc(u8, chunk_size);
    while (req.*[i] != new_line[0] or req.*[i + 1] != new_line[1]) {
        curr_chunk[i] = req.*[i];
        i += 1;
    }
    req.* = req.*[i + 2 .. req.len];
    return curr_chunk[0..i];
}

fn chop_space(req: *[]u8) ![]u8 {
    const space = ' ';
    var i: usize = 0;
    var initializedGpa = gpa(default_config){};
    const alloc = initializedGpa.allocator();
    var curr_chunk = try alloc.alloc(u8, chunk_size);
    while (i < req.len and req.*[i] != space) {
        curr_chunk[i] = req.*[i];
        i += 1;
    }
    if (i == req.len) {
        req.* = undefined;
    } else {
        req.* = req.*[i + 1 .. req.len];
    }
    return curr_chunk[0..i];
}

test "chop" {
    var arr: [100]u8 = undefined;
    var slice: []u8 = &arr;
    arr[0] = 'a';
    arr[1] = '\r';
    arr[2] = '\n';
    arr[3] = 'b';
    std.debug.print("{x}\n", .{slice});
    std.debug.print("{x}\n", .{chop_newline(&slice)});
    std.debug.print("{x}\n", .{slice});

    //    const new_slice = chop_by_new_line(test_slice.*);
    //    try std.testing.expectEqualSlices(u8, "abc", new_slice);
    //    try std.testing.expectEqualSlices(u8, "def", test_slice);
}

const std = @import("std");

pub fn min_usize(a: usize, b: usize) usize {
    return if (a < b) a else b;
}
pub fn max_usize(a: usize, b: usize) usize {
    return if (a > b) a else b;
}

const LOG_FILE = "log.log";
const allocator = std.heap.page_allocator;

pub fn write_to_log_file(comptime fmt: []const u8, args: anytype) !void {
    const file = std.fs.cwd().openFile(LOG_FILE, .{ .mode = .read_write }) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => {
            const dir = std.fs.cwd();
            const f = try dir.createFile(LOG_FILE, .{});
            f.close();
            try write_to_log_file(fmt, args);
            return;
        },
        else => return err,
    };
    try file.seekFromEnd(0);
    defer file.close();
    const out = try std.fmt.allocPrint(allocator, fmt, args);

    try file.writeAll(out);
}

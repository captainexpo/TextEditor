const std = @import("std");
const tApi = @import("./termapi/termapi.zig");

const Editor = @import("./editor.zig").Editor;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    //defer allocator.deinit(); // Ensure the allocator is properly deinitialized
    const args = try std.process.argsAlloc(allocator);
    var editor = try Editor.init(allocator, args);

    defer editor.deinit();
}

const std = @import("std");
const tApi = @import("./termapi/termapi.zig");

const Editor = @import("./editor.zig").Editor;
var editor: Editor = undefined;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    //defer allocator.deinit(); // Ensure the allocator is properly deinitialized
    const args = try std.process.argsAlloc(allocator);
    editor = try Editor.init(allocator, args);

    defer editor.deinit();
}

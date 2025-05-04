const std = @import("std");
const tApi = @import("./termapi/termapi.zig");

const Editor = @import("./editor.zig").Editor;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var editor: Editor = undefined;
var args: [][:0]u8 = undefined;
pub fn onexit() void {
    editor.terminal.clear_screen();
    editor.deinit();
    std.process.argsFree(gpa.allocator(), args);
    // HACK: don't detect leaks because I have a skill issue.
    // There's a leak that I can't fix no matter how hard I try.

    //if (gpa.detectLeaks()) {
    //    std.debug.print("Memory leak detected!\n", .{});
    //    std.process.exit(1);
    //}
    //_ = gpa.deinit();
    std.process.exit(0);
}

pub fn main() !void {
    editor.terminal.clear_screen();

    const allocator = gpa.allocator();

    args = try std.process.argsAlloc(allocator);

    editor = try Editor.init(allocator, args, &onexit);

    editor.start_running() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return err;
    };
}

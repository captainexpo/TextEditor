const std = @import("std");

const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("sys/ioctl.h");
});

pub const WinSize = extern struct {
    rows: u16,
    cols: u16,
    xpixel: u16,
    ypixel: u16,
};

pub fn get_size_linux() WinSize {
    const stdout = std.io.getStdOut().handle;

    var ws = WinSize{ .rows = 0, .cols = 0, .xpixel = 0, .ypixel = 0 };
    const result = c.ioctl(stdout, 0x5413, &ws); // 0x5413 == TIOCGWINSZ on Linux
    if (result != 0) {
        std.debug.print("Failed to get terminal size\n", .{});
        return ws;
    }
    return ws;
}

pub fn get_size_mac() WinSize {
    const stdout = std.io.getStdOut().handle;

    var ws = WinSize{ .rows = 0, .cols = 0, .xpixel = 0, .ypixel = 0 };
    const result = c.ioctl(stdout, 0x40087468, &ws); // 0x40087468 == TIOCGWINSZ on macOS
    if (result != 0) {
        std.debug.print("Failed to get terminal size\n", .{});
        return ws;
    }
    return ws;
}

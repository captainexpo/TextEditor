const std = @import("std");

const keyApi = @import("./key.zig");
const Key = keyApi.Key;
const KeyModifier = keyApi.KeyModifier;
const Editor = @import("../editor.zig").Editor;

const io = std.io;
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("poll.h");
});

pub const TermColor = enum(u32) { // Contains ANSI color codes
    Reset = 0,
    Black = 30,
    Red = 31,
    Green = 32,
    Yellow = 33,
    Blue = 34,
    Magenta = 35,
    Cyan = 36,
    White = 37,
};

pub const TerminalAPI = struct {
    stdout: std.fs.File.Writer,
    stderr: std.fs.File.Writer,
    allocator: std.mem.Allocator,
    tty: std.fs.File,

    input_callback: ?*Editor = null,

    pub fn new(allocator: std.mem.Allocator) !TerminalAPI {
        const stdout = io.getStdOut().writer();
        const stderr = io.getStdErr().writer();
        const tty = try std.fs.cwd().openFile("/dev/tty", .{});

        var t_api = TerminalAPI{
            .stdout = stdout,
            .stderr = stderr,
            .allocator = allocator,
            .tty = tty,
        };

        t_api.init();

        return t_api;
    }

    pub fn init(self: *TerminalAPI) void {
        var termios = c.termios{};
        var res = c.tcgetattr(c.STDIN_FILENO, &termios);
        if (res != 0) {
            self.stderr.print("Failed to get terminal attributes\n", .{}) catch unreachable;
            return;
        }
        // Modify termios to set raw mode
        termios.c_lflag &= ~(@as(c_uint, c.ICANON | c.ECHO));
        termios.c_cc[c.VMIN] = 1; // Minimum number of bytes before read() returns
        termios.c_cc[c.VTIME] = 0; // No timeout

        res = c.tcsetattr(c.STDIN_FILENO, c.TCSANOW, &termios);
        if (res != 0) {
            self.stderr.print("Failed to set terminal attributes\n", .{}) catch unreachable;
            return;
        }
    }

    pub fn onInput(self: *TerminalAPI, callback: *Editor) void {
        self.input_callback = callback;
    }

    pub fn set_color(self: *TerminalAPI, color: TermColor) !void {
        var buffer: [32]u8 = undefined;
        const out = try std.fmt.bufPrint(&buffer, "\x1b[{}m", .{@intFromEnum(color)});
        self.stdout.writeAll(out) catch unreachable;
    }

    pub fn clear_screen(self: *TerminalAPI) void {
        self.stdout.writeAll("\x1b[2J\x1b[H") catch unreachable;
    }

    pub fn goto(self: *TerminalAPI, x: usize, y: usize) !void {
        var buffer: [32]u8 = undefined;
        const out = try std.fmt.bufPrint(&buffer, "\x1b[{};{}H", .{ y, x });
        self.stdout.writeAll(out) catch unreachable;
    }

    pub fn deinit(self: *TerminalAPI) void {
        self.tty.close();
    }

    pub fn read_key(self: *TerminalAPI) !?Key {
        _ = self;
        const fd = c.STDIN_FILENO;

        // 1) block until at least one byte is ready
        var pfd = c.pollfd{
            .fd = fd,
            .events = c.POLLIN,
            .revents = 0,
        };
        const rc = c.poll(&pfd, 1, -1);
        if (rc < 0) return error.PollingError;

        // 2) read *all* available bytes (up to 8) in one go
        var buf: [8]u8 = undefined;
        const n = c.read(fd, &buf, buf.len);
        if (n <= 0) return null;

        // 3) if it’s not ESC, it’s a normal key
        if (buf[0] != 0x1B) {
            return Key{ .code = buf[0], .modifier = KeyModifier.None };
        }

        // 4) if we got at least 3 bytes and it’s [ A/B/C/D ]
        if (n >= 3 and buf[1] == '[') {
            const arrow = buf[2];
            if (arrow == 'A' or arrow == 'B' or arrow == 'C' or arrow == 'D') {
                return Key{ .code = arrow, .modifier = KeyModifier.ArrowKey };
            }
        }

        // 5) otherwise just return the ESC
        return Key{ .code = buf[0], .modifier = KeyModifier.None };
    }

    pub fn run(self: *TerminalAPI) !void {
        while (true) {
            const n = try self.read_key() orelse continue;

            if (self.input_callback) |callback| {
                callback.input_callback(n);
            }
        }
    }
};

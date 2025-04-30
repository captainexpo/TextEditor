const std = @import("std");

const keyApi = @import("./key.zig");
const Key = keyApi.Key;
const KeyModifier = keyApi.KeyModifier;
const Editor = @import("../editor.zig").Editor;
const utils = @import("../utils.zig");

const io = std.io;
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("poll.h");
});

const read_term_key = @cImport({
    @cInclude("get_input.h");
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

        read_term_key.enable_raw_mode();

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
        read_term_key.enable_raw_mode();

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

        const key = read_term_key.get_input();
        const code = @as(u8, @truncate(key.keyCode));
        utils.write_to_log_file("Key code: {}, {}\n", .{ code, key.modifiers }) catch unreachable;
        return Key{ .code = code, .modifier = @as(u32, key.modifiers) };
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

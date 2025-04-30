const std = @import("std");
const tApi = @import("./termapi/termapi.zig");

const keyApi = @import("./termapi/key.zig");
const Key = keyApi.Key;
const T_API = keyApi.T_API;

const Cursor = @import("cursor.zig").Cursor;
const Contents = @import("contentseditor.zig").Contents;

const get_size = @import("./terminalsize.zig").unified_get_size;

const utils = @import("utils.zig");

pub const EditorMode = enum {
    Edit,
    Command,
};

pub const Editor = struct {
    terminal: tApi.TerminalAPI,
    cursor: Cursor,
    contents: Contents,
    line_disp_min: usize,
    line_disp_max: usize,
    allocator: std.mem.Allocator,
    mode: EditorMode = .Edit,
    debug_line: []const u8 = "",

    current_command: std.ArrayList(u8) = undefined,

    pub fn init(allocator: std.mem.Allocator, args: [][:0]u8) !Editor {
        var contents = try Contents.init(allocator, 512);
        if (args.len >= 2) {
            try contents.load_from_file(args[1], allocator, contents.max_line_len);
        }

        var cursor = Cursor{ .x = 0, .y = 0 };
        var terminal = try tApi.TerminalAPI.new(allocator);

        var editor = Editor{
            .terminal = terminal,
            .cursor = cursor,
            .contents = contents,
            .line_disp_min = 0,
            .line_disp_max = Editor.get_editor_height(),
            .allocator = allocator,
            .mode = .Edit,
            .current_command = std.ArrayList(u8).init(allocator),
        };

        terminal.init();
        terminal.clear_screen();

        contents.output(&cursor, &terminal, 0, editor.line_disp_max);

        terminal.onInput(&editor);
        try terminal.run();

        return editor;
    }

    pub fn get_editor_height() usize {
        const f = get_size().rows;
        if (f < 5) return 5;
        return f - 5; // HACK: this is jank as fuck, but it's fine
    }

    pub fn re_output(self: *Editor) void {
        self.contents.output(&self.cursor, &self.terminal, self.line_disp_min, self.line_disp_max);
        std.debug.print("Mode: {s}\n", .{@tagName(self.mode)});
        std.debug.print("Dbg: {s}\n", .{self.debug_line});
        std.debug.print("CMD: {s}", .{self.current_command.items});
    }

    pub fn input_callback(self: *Editor, key: Key) void {
        if (key.modifier ^ T_API.ARROW_KEY_MODIFIER == 0) {
            self.handle_arrow_key(key.code);
        } else {
            self.handle_regular_key(key.code);
        }
        self.re_output();
    }

    fn handle_arrow_key(self: *Editor, code: u8) void {
        if (self.mode != .Edit) return;
        switch (code) {
            0x41 => self.move_cursor_up(), // Up
            0x42 => self.move_cursor_down(), // Down
            0x43 => self.move_cursor_right(), // Right
            0x44 => self.move_cursor_left(), // Left
            else => {},
        }
    }

    fn handle_escape(self: *Editor) void {
        if (self.mode == EditorMode.Edit) {
            self.mode = EditorMode.Command;
        }
    }

    fn handle_regular_key(self: *Editor, code: u8) void {
        switch (code) {
            0x7F => self.handle_backspace(), // Backspace
            0x0A => self.handle_enter(), // Enter
            0x1B => self.handle_escape(),

            // Shift
            else => self.handle_character_input(code),
        }
    }

    fn move_cursor_up(self: *Editor) void {
        const cl = self.contents.contents.items[self.cursor.y];
        self.contents.contents.items[self.cursor.y].last_pos = self.cursor.x;
        self.cursor.y -= if (self.cursor.y > 0) 1 else 0;
        const nl = self.contents.get_or_create_line(self.cursor.y);
        // if length of previous line is == 0, jump to line's last position, else go to cursor's reg pos
        self.cursor.x = if (cl.len > 0) utils.min_usize(self.cursor.x, nl.len) else nl.*.last_pos;
        while (self.cursor.y < self.line_disp_min and self.line_disp_min > 0) {
            self.line_disp_min -= 1;
            self.line_disp_max = self.line_disp_min + Editor.get_editor_height();
        }
    }

    fn move_cursor_down(self: *Editor) void {
        const cl = self.contents.contents.items[self.cursor.y];
        self.contents.contents.items[self.cursor.y].last_pos = self.cursor.x;
        self.cursor.y += 1;
        const nl = self.contents.get_or_create_line(self.cursor.y);
        // if length of previous line is == 0, jump to line's last position, else go to cursor's reg pos
        self.cursor.x = if (cl.len > 0) utils.min_usize(self.cursor.x, nl.len) else nl.*.last_pos;
        while (self.cursor.y > self.line_disp_max) {
            self.line_disp_max += 1;
            const height = Editor.get_editor_height();
            self.line_disp_min = self.line_disp_max - if (height <= self.line_disp_max) height else self.line_disp_max;
            if (self.line_disp_min < 0) self.line_disp_min = 0;
        }
    }

    fn move_cursor_right(self: *Editor) void {
        self.cursor.x += if (self.cursor.x < self.contents.get_or_create_line(self.cursor.y).*.len) 1 else 0;
    }

    fn move_cursor_left(self: *Editor) void {
        self.cursor.x -= if (self.cursor.x > 0) 1 else 0;
    }

    fn handle_backspace(self: *Editor) void {
        if (self.mode == .Command) {
            if (self.current_command.items.len == 0) return;
            _ = self.current_command.pop();
            std.debug.print("{c}", .{0x7F});
            return;
        }
        if (self.cursor.x > 0) {
            self.cursor.x -= 1;
            self.contents.bulk_delete(&self.cursor, 1);
        } else {
            const line = self.contents.contents.orderedRemove(self.cursor.y);
            self.cursor.y -= if (self.cursor.y > 0) 1 else 0;
            const nl = self.contents.get_or_create_line(self.cursor.y);
            self.cursor.x = nl.*.len;
            self.contents.write_all(self.cursor.y, nl.*.len, line.data[0..line.len], true) catch |err| {
                std.debug.print("Error writing to contents: {?}\n", .{err});
            };
        }
    }

    fn parse_command_args(self: *Editor, command: []const u8) ![][]const u8 {
        // Split by spaces, handling quotes
        var args: std.ArrayList([]const u8) = std.ArrayList([]const u8).init(self.allocator);
        var start: usize = 0;
        var in_quotes: bool = false;

        for (command, 0..command.len) |c, i| {
            if (c == '"' and (i == 0 or command[i - 1] != '\\')) {
                in_quotes = !in_quotes;
                if (!in_quotes and i > start) {
                    const arg = command[start..i];
                    try args.append(arg);
                    start = i + 1;
                } else if (in_quotes) {
                    start = i + 1;
                }
            } else if (c == ' ' and !in_quotes) {
                if (i > start) {
                    const arg = command[start..i];
                    try args.append(arg);
                }
                start = i + 1;
            }
        }

        if (start < command.len) {
            const arg = command[start..];
            try args.append(arg);
        }

        return try args.toOwnedSlice();
    }
    fn set_dbg_line(self: *Editor, comptime fmt: []const u8, args: anytype) void {
        self.debug_line = std.fmt.allocPrint(self.allocator, fmt, args) catch unreachable;
    }
    // Command handler
    fn quit_cmd(self: *Editor, args: [][]const u8) void {
        _ = args;
        self.deinit();
        std.process.exit(0);
    }
    fn save_cmd(self: *Editor, args: [][]const u8) void {
        _ = args;
        self.contents.save_to_file(self.contents.open_path) catch |err| {
            std.debug.print("Error saving to file: {?}\n", .{err});
        };
    }
    fn to_edit_cmd(self: *Editor, args: [][]const u8) void {
        _ = args;
        self.mode = .Edit;
    }
    fn to_line_cmd(self: *Editor, args: [][]const u8) void {
        // Jump to line
        if (args.len == 1) {
            const line = std.fmt.parseInt(u32, args[0], 10) catch |err| {
                self.set_dbg_line("Error parsing line number: {?}\n", .{err});
                return;
            };
            if (line > 0 and line <= self.contents.contents.items.len) {
                self.cursor.y = line - 1;
                self.cursor.x = 0;
                self.line_disp_min = self.cursor.y;
                self.line_disp_max = self.cursor.y + Editor.get_editor_height();
            } else {
                self.debug_line = "Line number out of range";
            }
        } else {
            self.debug_line = "Usage: <line_number>";
        }
    }

    fn change_file_cmd(self: *Editor, args: [][]const u8) void {
        if (args.len == 2) {
            self.contents.load_from_file(args[1], self.allocator, self.contents.max_line_len) catch |err| {
                self.set_dbg_line("Error loading file: {?}\n", .{err});
            };
            self.cursor.y = 0;
            self.cursor.x = 0;
            self.line_disp_min = 0;
            self.line_disp_max = Editor.get_editor_height();
        } else {
            self.set_dbg_line("Usage: <file_path>", .{});
        }
    }

    fn run_os_cmd(self: *Editor, args: [][]const u8) void {
        if (args.len == 2) {
            const output = std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = args[1..],
            }) catch |err| {
                self.set_dbg_line("Error executing command: {?}\n", .{err});
                return;
            };
            self.set_dbg_line("{s}\n", .{output.stdout});
        } else {
            self.debug_line = "Usage: <command>";
        }
    }

    fn clear_dbg_cmd(self: *Editor, args: [][]const u8) void {
        _ = args;
        self.debug_line = "";
    }
    fn is_valid_line_idx(self: *Editor, line: usize) bool {
        return line >= 0 and line < self.contents.contents.items.len;
    }

    fn del_line_cmd(self: *Editor, args: [][]const u8) void {
        if (args.len != 2) {
            self.set_dbg_line("Usage: dl <line>", .{});
            return;
        }
        const line = std.fmt.parseInt(usize, args[1], 10) catch |err| {
            self.set_dbg_line("{?}", .{err});
            return;
        };
        if (!self.is_valid_line_idx(line)) {
            self.set_dbg_line("Line out of range", .{});
            return;
        }

        _ = self.contents.contents.orderedRemove(line - 1);
    }
    fn handle_command(self: *Editor) void {
        if (self.current_command.items.len == 0) return;

        var command_dispatcher = std.StringHashMap(*const fn (self: *Editor, args: [][]const u8) void).init(self.allocator);
        command_dispatcher.put(@as([]const u8, "q"), &Editor.quit_cmd) catch unreachable;
        command_dispatcher.put(@as([]const u8, "s"), &Editor.save_cmd) catch unreachable;
        command_dispatcher.put(@as([]const u8, "e"), &Editor.to_edit_cmd) catch unreachable;
        command_dispatcher.put(@as([]const u8, "chf"), &Editor.change_file_cmd) catch unreachable;
        command_dispatcher.put(@as([]const u8, ">"), &Editor.run_os_cmd) catch unreachable;
        command_dispatcher.put(@as([]const u8, "clr"), &Editor.clear_dbg_cmd) catch unreachable;
        command_dispatcher.put(@as([]const u8, "dl"), &Editor.del_line_cmd) catch unreachable;
        const command = self.current_command.items;
        const args = self.parse_command_args(command) catch |err| {
            std.debug.print("Error parsing command: {?}\n", .{err});
            return;
        };
        const command_func = command_dispatcher.get(args[0]);
        if (command_func) |func| {
            func(self, args);
        } else if (std.ascii.isDigit(command[0])) {
            self.to_line_cmd(args);
        } else {
            self.debug_line = std.fmt.allocPrint(self.allocator, "Unknown command {s}", .{command}) catch unreachable;
        }
        self.current_command.clearRetainingCapacity();
    }

    fn handle_enter(self: *Editor) void {
        if (self.mode == .Command) {
            self.handle_command();
            return;
        }
        self.contents.contents.items[self.cursor.y].last_pos = self.cursor.x;
        self.contents.newline(self.cursor.y, self.cursor.x) catch |err| {
            std.debug.print("Error creating newline: {?}\n", .{err});
        };
        self.cursor.y += 1;
        self.cursor.x = 0;
        while (self.cursor.y > self.line_disp_max) {
            self.line_disp_max += 1;
            const height = Editor.get_editor_height();
            self.line_disp_min = self.line_disp_max - if (height <= self.line_disp_max) height else self.line_disp_max;
            if (self.line_disp_min < 0) self.line_disp_min = 0;
        }
    }

    fn handle_character_input(self: *Editor, code: u8) void {
        if (self.mode == .Command) {
            self.current_command.append(code) catch unreachable;
            std.debug.print("{c}", .{code});
            return;
        }
        self.contents.write(self.cursor.y, self.cursor.x, code, true) catch |err| {
            std.debug.print("Error writing to contents: {?}\n", .{err});
        };
        self.cursor.x += 1;
    }

    pub fn deinit(self: *Editor) void {
        self.contents.deinit();
        self.terminal.deinit();
    }
};

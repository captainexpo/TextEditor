const std = @import("std");
const tApi = @import("./termapi/termapi.zig");

const keyApi = @import("./termapi/key.zig");
const Key = keyApi.Key;
const KeyModifier = keyApi.KeyModifier;

const Cursor = @import("cursor.zig").Cursor;
const Contents = @import("contentseditor.zig").Contents;

const get_size = @import("./terminalsize.zig").get_size_linux;

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

    pub fn input_callback(self: *Editor, key: Key) void {
        if (key.modifier == KeyModifier.ArrowKey) {
            self.handle_arrow_key(key.code);
        } else {
            self.handle_regular_key(key.code);
        }
        self.contents.output(&self.cursor, &self.terminal, self.line_disp_min, self.line_disp_max);
        std.debug.print("Mode: {s}\n", .{@tagName(self.mode)});
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
            else => self.handle_character_input(code),
        }
    }

    fn move_cursor_up(self: *Editor) void {
        self.contents.contents.items[self.cursor.y].last_pos = self.cursor.x;
        self.cursor.y -= if (self.cursor.y > 0) 1 else 0;
        self.cursor.x = self.contents.get_or_create_line(self.cursor.y).*.last_pos;
        while (self.cursor.y < self.line_disp_min and self.line_disp_min > 0) {
            self.line_disp_min -= 1;
            self.line_disp_max = self.line_disp_min + Editor.get_editor_height();
        }
    }

    fn move_cursor_down(self: *Editor) void {
        self.contents.contents.items[self.cursor.y].last_pos = self.cursor.x;
        self.cursor.y += 1;
        self.cursor.x = self.contents.get_or_create_line(self.cursor.y).*.last_pos;
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
            _ = self.current_command.pop();
            std.debug.print("{c}", .{0x7F});
            return;
        }
        if (self.cursor.x > 0) {
            self.cursor.x -= 1;
            self.contents.bulk_delete(&self.cursor, 1);
        } else {
            const line = self.contents.contents.orderedRemove(self.cursor.y);
            line.deinit(self.allocator);
            self.cursor.y -= if (self.cursor.y > 0) 1 else 0;
            self.cursor.x = self.contents.get_or_create_line(self.cursor.y).*.len;
        }
    }

    fn handle_command(self: *Editor) void {
        if (self.current_command.items.len == 0) return;
        const command = self.current_command.items;
        if (std.mem.eql(u8, command, "q")) {
            std.process.exit(0);
        } else if (std.mem.eql(u8, command, "s")) {
            self.contents.save_to_file(self.contents.open_path) catch |err| {
                std.debug.print("Error saving to file: {?}\n", .{err});
            };
        } else if (std.mem.eql(u8, command, "e")) {
            self.mode = .Edit;
        } else {
            std.debug.print("Unknown command: {s}\n", .{command});
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

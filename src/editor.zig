const std = @import("std");
const tApi = @import("./termapi/termapi.zig");

const keyApi = @import("./termapi/key.zig");
const Key = keyApi.Key;
const KeyModifier = keyApi.KeyModifier;

const Cursor = @import("cursor.zig").Cursor;
const Contents = @import("contentseditor.zig").Contents;

const get_size = @import("./terminalsize.zig").get_size_mac;

pub const Editor = struct {
    terminal: tApi.TerminalAPI,
    cursor: Cursor,
    contents: Contents,
    line_disp_min: usize,
    line_disp_max: usize,
    allocator: std.mem.Allocator,

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
        };

        terminal.init();
        terminal.clear_screen();

        contents.output(&cursor, &terminal, 0, editor.line_disp_max);

        terminal.onInput(&editor);
        try terminal.run();

        return editor;
    }

    pub fn get_editor_height() usize {
        const f = get_size().rows - 5;
        if (f < 5) return 5;
        return f; // HACK: this is jank as fuck, but it's fine
    }

    pub fn input_callback(self: *Editor, key: Key) void {
        if (key.modifier == KeyModifier.ArrowKey) {
            switch (key.code) {
                0x41 => {
                    self.contents.contents.items[self.cursor.y].last_pos = self.cursor.x;
                    self.cursor.y -= if (self.cursor.y > 0) 1 else 0;
                    self.cursor.x = self.contents.get_or_create_line(self.cursor.y).*.last_pos;
                    while (self.cursor.y < self.line_disp_min and self.line_disp_min > 0) {
                        self.line_disp_min -= 1;
                        self.line_disp_max = self.line_disp_min + Editor.get_editor_height();
                    }
                }, // Up
                0x42 => {
                    self.contents.contents.items[self.cursor.y].last_pos = self.cursor.x;
                    self.cursor.y += 1;
                    self.cursor.x = self.contents.get_or_create_line(self.cursor.y).*.last_pos;
                    while (self.cursor.y > self.line_disp_max) {
                        self.line_disp_max += 1;
                        self.line_disp_min = self.line_disp_max - Editor.get_editor_height();
                        if (self.line_disp_min < 0) self.line_disp_min = 0;
                    }
                }, // Down
                0x43 => {
                    self.cursor.x += if (self.cursor.x < self.contents.get_or_create_line(self.cursor.y).*.len) 1 else 0;
                }, // Right
                0x44 => {
                    self.cursor.x -= if (self.cursor.x > 0) 1 else 0;
                }, // Left
                else => {},
            }
        } else {
            switch (key.code) {
                // Backspace
                0x7F => {
                    if (self.cursor.x > 0) {
                        self.cursor.x -= 1;
                        self.contents.bulk_delete(&self.cursor, 1);
                    } else {
                        const line = self.contents.contents.orderedRemove(self.cursor.y);
                        line.deinit(self.allocator);
                        self.cursor.y -= if (self.cursor.y > 0) 1 else 0;
                        self.cursor.x = self.contents.get_or_create_line(self.cursor.y).*.len;
                    }
                },
                // Enter
                0x0A => {
                    self.contents.contents.items[self.cursor.y].last_pos = self.cursor.x;
                    self.contents.newline(self.cursor.y, self.cursor.x) catch |err| {
                        std.debug.print("Error creating newline: {?}\n", .{err});
                    };
                    self.cursor.y += 1;
                    self.cursor.x = 0;
                    while (self.cursor.y > self.line_disp_max) {
                        self.line_disp_max += 1;
                        self.line_disp_min = self.line_disp_max - Editor.get_editor_height();
                        if (self.line_disp_min < 0) self.line_disp_min = 0;
                    }
                },
                else => {
                    self.contents.write(self.cursor.y, self.cursor.x, key.code) catch |err| {
                        std.debug.print("Error writing to contents: {?}\n", .{err});
                    };
                    self.cursor.x += 1;
                },
            }
        }
        self.contents.output(&self.cursor, &self.terminal, self.line_disp_min, self.line_disp_max);
        // catch |err| {
        //    std.debug.print("Error outputting contents: {?}\n", .{err});
        //};
    }

    pub fn deinit(self: *Editor) void {
        self.contents.deinit();
        self.terminal.deinit();
    }
};

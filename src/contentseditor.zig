const std = @import("std");
const TerminalApi = @import("./termapi/termapi.zig").TerminalAPI;
const Cursor = @import("cursor.zig").Cursor;
const utils = @import("./utils.zig");
const tApi = @import("./termapi/termapi.zig");
const re = @cImport(@cInclude("regez.h"));

// This is a comment
pub const LineData = struct {
    data: []u8,
    len: usize,
    last_pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, max_line_len: usize) !*LineData {
        var buf = try allocator.alloc(u8, max_line_len);
        for (0..max_line_len) |i| {
            buf[i] = 0;
        }
        const l = try allocator.create(LineData);
        l.data = buf;
        l.len = 0;
        l.last_pos = 0;
        l.allocator = allocator;
        return l;
    }

    pub fn deinit(self: *LineData) void {
        std.debug.print("deinit line data\n", .{});
        self.allocator.free(self.data);
        self.allocator.destroy(self);
    }

    pub fn replace(self: *LineData, allocator: std.mem.Allocator, find: []const u8, rep: []const u8) !void {
        utils.write_to_log_file("finding '{s}' with '{s}'\n", .{ find, rep }) catch unreachable;

        // Where find is a regex
        const find_cstr = try std.fmt.allocPrintZ(allocator, "{s}", .{find});
        defer allocator.free(find_cstr);

        const rep_cstr = try std.fmt.allocPrintZ(allocator, "{s}", .{rep});
        defer allocator.free(rep_cstr);

        const output: [:0]u8 = allocator.allocSentinel(u8, self.len, 0) catch unreachable;
        defer allocator.free(output);

        const input = std.fmt.allocPrintZ(allocator, "{s}", .{self.data[0..self.len]}) catch unreachable;
        defer allocator.free(input);

        const sizeof_output: c_uint = @as(c_uint, @intCast(8 * (self.len + 1)));

        re.regex_replace(find_cstr, rep_cstr, input, output, sizeof_output);

        self.len = output.len;
        @memcpy(self.data[0..self.len], output);
        utils.write_to_log_file("{d}: {s}\n", .{ self.len, self.data }) catch |err| {
            std.debug.print("Error writing to log file: {?}\n", .{err});
            return;
        };
    }

    pub fn get_data(self: *LineData) []const u8 {
        return self.data[0..self.len];
    }
};

pub const Contents = struct {
    allocator: std.mem.Allocator,
    max_line_len: usize,
    contents: std.ArrayList(*LineData),
    open_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, max_line_len: usize) !Contents {
        return Contents{
            .allocator = allocator,
            .max_line_len = max_line_len,
            .contents = std.ArrayList(*LineData).init(allocator),
            .open_path = undefined,
        };
    }

    pub fn write(self: *Contents, line: usize, col: usize, data: u8, is_insert: bool) !void {
        while (line >= self.contents.items.len) {
            self.contents.append(LineData.init(self.allocator, self.max_line_len) catch unreachable) catch unreachable;
        }
        if (col >= self.max_line_len) {
            return error.OutOfBounds;
        }
        var line_ptr = self.contents.items[line];

        if (is_insert) {
            if (line_ptr.len + 1 > self.max_line_len) {
                return error.OutOfBounds;
            }
            var i: usize = line_ptr.len;
            while (i > col) : (i -= 1) {
                line_ptr.data[i] = line_ptr.data[i - 1];
            }
            line_ptr.len += 1;
        }

        line_ptr.data[col] = data;

        if (line_ptr.len < col + 1) {
            line_ptr.len = col + 1;
        }
    }
    pub fn write_all(self: *Contents, line: usize, col: usize, data: []const u8, is_insert: bool) !void {
        if (col + data.len > self.max_line_len) {
            return error.OutOfBounds;
        }
        const line_ptr = self.get_or_create_line(line);

        if (is_insert) {
            if (line_ptr.len + data.len > self.max_line_len) {
                return error.OutOfBounds;
            }
            var i: usize = line_ptr.len;
            while (i > col) : (i -= 1) {
                line_ptr.data[i + data.len - 1] = line_ptr.data[i - 1];
            }
            line_ptr.len += data.len;
        }

        @memcpy(line_ptr.data[col .. col + data.len], data);

        if (line_ptr.len < col + data.len) {
            line_ptr.len = col + data.len;
        }
    }

    pub fn output(self: *Contents, cursor: *Cursor, terminal: *TerminalApi, min: usize, max: usize) void {
        terminal.clear_screen();
        const from: usize = min;
        const to: usize = max + 1;

        const MAX_LINE_DIGITS: comptime_int = 5;

        for (from..to) |i| {
            const line: *LineData = if (i < self.contents.items.len) self.contents.items[i] else undefined;
            const line_digits: usize = @as(usize, @intFromFloat(@floor(@log10(@as(f32, @as(f32, @floatFromInt(i)) + 1))) + 1));
            if (cursor.y == i) {
                std.debug.print("{d}{s}| {s}", .{ i + 1, (" " ** MAX_LINE_DIGITS)[0 .. MAX_LINE_DIGITS - line_digits], line.*.data[0..cursor.x] });
                terminal.set_color(tApi.TermColor.Red) catch unreachable;
                std.debug.print("|", .{});
                terminal.set_color(tApi.TermColor.White) catch unreachable;
                std.debug.print("{s}\n", .{line.*.data[cursor.x..line.*.len]});
                continue;
            }
            if (i >= self.contents.items.len) {
                std.debug.print("{s}|\n", .{(" " ** MAX_LINE_DIGITS)[0..MAX_LINE_DIGITS]});
            } else {
                std.debug.print("{d}{s}| {s}\n", .{ i + 1, (" " ** MAX_LINE_DIGITS)[0 .. MAX_LINE_DIGITS - line_digits], line.get_data() });
            }
        }
        std.debug.print("{d} {d}\n", .{ min, max });
    }
    // This is another fucking comment :D

    pub fn bulk_delete(self: *Contents, cursor: *Cursor, rawcount: usize) void {
        if (cursor.y >= self.contents.items.len) {
            return;
        }
        var count: usize = rawcount;
        const line_ptr = self.contents.items[cursor.y];
        if (cursor.x + count > line_ptr.*.len) {
            count = line_ptr.*.len - cursor.x;
        }
        for (cursor.x..line_ptr.*.len - count) |i| {
            line_ptr.*.data[i] = line_ptr.*.data[i + count];
        }
        for (line_ptr.*.len - count..line_ptr.*.len) |i| {
            line_ptr.*.data[i] = 0;
        }
        line_ptr.*.len -= count;
    }
    pub fn newline(self: *Contents, line: usize, col: usize) !void {
        var old_line = self.contents.items[line];
        var new_line = LineData.init(self.allocator, self.max_line_len) catch unreachable;
        try self.contents.insert(line + 1, new_line);
        // Copy the data from the end of the old line to the new line
        @memcpy(new_line.data[0 .. old_line.len - col], old_line.data[col..old_line.len]);
        // Set the length of the new line
        new_line.len = old_line.len - col;
        // Set the length of th e old line
        old_line.len = col;
    }
    pub fn get_or_create_line(self: *Contents, line: usize) *LineData {
        while (line >= self.contents.items.len) {
            self.contents.append(LineData.init(self.allocator, self.max_line_len) catch unreachable) catch unreachable;
        }
        return self.contents.items[line];
    }

    pub fn load_from_file(self: *Contents, path: []const u8, allocator: std.mem.Allocator, max_lines: usize) !void {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            std.debug.print("Error opening file: {?}\n", .{err});
            return;
        };
        self.open_path = path;
        const data = file.readToEndAlloc(allocator, self.max_line_len * max_lines) catch |err| {
            std.debug.print("Error reading file: {?}\n", .{err});
            return;
        };
        // Split data by newlines
        self.contents = std.ArrayList(*LineData).init(allocator);

        var cur_idx: usize = 0;

        var current_line = try LineData.init(allocator, self.max_line_len);

        for (0..data.len) |i| {
            if (cur_idx + 1 > self.max_line_len) {
                return error.LineTooLong;
            }

            const cur_char = data[i];
            if (cur_char == '\n') {
                current_line.len = cur_idx;
                cur_idx = 0;
                try self.contents.append(current_line);
                current_line = try LineData.init(allocator, self.max_line_len);
                continue;
            }

            // Other character
            current_line.data[cur_idx] = cur_char;

            cur_idx += 1;
        }
        try self.contents.append(current_line);

        allocator.free(data);
    }

    pub fn save_to_file(self: *Contents, path: []const u8) !void {
        const dir = std.fs.cwd();
        const file = dir.createFile(path, .{}) catch |err| {
            std.debug.print("Error creating file: {?}\n", .{err});
            return;
        };
        defer file.close();
        for (self.contents.items) |line| {
            try file.writeAll(line.data[0..line.len]);
            try file.writeAll("\n");
        }
    }

    pub fn deinit(self: *Contents) void {
        for (self.contents.items) |line| {
            line.*.deinit();
        }
        self.contents.deinit();
    }
};

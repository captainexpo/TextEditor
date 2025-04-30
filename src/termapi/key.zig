const std = @import("std");

pub const T_API = @cImport({
    @cInclude("get_input.h");
});

pub const Key = struct {
    code: u8,
    modifier: u32,
};

const std = @import("std");

pub const KeyModifier = enum {
    None,
    ArrowKey,
};

pub const Key = struct {
    code: u8,
    modifier: KeyModifier,
};

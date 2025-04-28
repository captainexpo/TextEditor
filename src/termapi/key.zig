const std = @import("std");

pub const KeyModifier = enum {
    None,
    ArrowKey,
    Shift,
    Control,
    Alt,
};

pub const Key = struct {
    code: u8,
    modifier: KeyModifier,
    sub_modifier: KeyModifier = undefined,
};

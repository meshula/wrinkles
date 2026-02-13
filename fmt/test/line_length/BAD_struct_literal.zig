const std = @import("std");

const Config = struct {
    name: []const u8,
    value: i32,
    enabled: bool,
    threshold: f32,
};

pub fn create_config() Config {
    // Struct literal broken across lines
    return .{
        .name = "default",
        .value = 42,
        .enabled = true,
        .threshold = 0.5,
    };
}

test "struct literal" {
    const cfg = create_config();
    try std.testing.expectEqual(@as(i32, 42), cfg.value);
}

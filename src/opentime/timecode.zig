//! SMPTE Timecode Utilities
//!
//! Provides parsing, formatting, and conversion between SMPTE timecode strings
//! and continuous time values. Supports standard frame rates including drop-frame
//! timecode for 29.97 and 59.94 fps.

const std = @import("std");
const ordinate = @import("ordinate.zig");

/// Standard SMPTE timecode frame rates
pub const TimecodeRate = enum(u8) {
    rate_23_976 = 0,  // 24 * 1000 / 1001
    rate_24 = 1,
    rate_25 = 2,
    rate_29_97 = 3,   // 30 * 1000 / 1001 (NTSC)
    rate_30 = 4,
    rate_47_952 = 5,  // 48 * 1000 / 1001
    rate_48 = 6,
    rate_50 = 7,
    rate_59_94 = 8,   // 60 * 1000 / 1001 (NTSC HD)
    rate_60 = 9,

    /// Get the actual frame rate as f64.
    pub fn as_f64(
        self: @This(),
    ) f64
    {
        return switch (self) {
            .rate_23_976 => 24000.0 / 1001.0,
            .rate_24 => 24.0,
            .rate_25 => 25.0,
            .rate_29_97 => 30000.0 / 1001.0,
            .rate_30 => 30.0,
            .rate_47_952 => 48000.0 / 1001.0,
            .rate_48 => 48.0,
            .rate_50 => 50.0,
            .rate_59_94 => 60000.0 / 1001.0,
            .rate_60 => 60.0,
        };
    }

    /// Nominal integer fps (for frame counting).
    pub fn nominal_fps(
        self: @This(),
    ) u8
    {
        return switch (self) {
            .rate_23_976, .rate_24 => 24,
            .rate_25 => 25,
            .rate_29_97, .rate_30 => 30,
            .rate_47_952, .rate_48 => 48,
            .rate_50 => 50,
            .rate_59_94, .rate_60 => 60,
        };
    }

    /// Whether this rate supports drop-frame timecode.
    pub fn supports_drop_frame(
        self: @This(),
    ) bool
    {
        return self == .rate_29_97 or self == .rate_59_94;
    }

    /// Number of frames dropped per minute (except every 10th minute).
    pub fn drop_frames_per_minute(
        self: @This(),
    ) u8
    {
        return switch (self) {
            .rate_29_97 => 2,
            .rate_59_94 => 4,
            else => 0,
        };
    }
};

/// Error set for timecode operations.
pub const TimecodeError = error{
    invalid_timecode_string,
    invalid_timecode_rate,
    hours_out_of_range,
    minutes_out_of_range,
    seconds_out_of_range,
    frames_out_of_range,
    negative_value,
    drop_frame_not_supported,
    dropped_frame_number,
};

/// SMPTE timecode representation.
pub const Timecode = struct {
    hours: u8 = 0,
    minutes: u8 = 0,
    seconds: u8 = 0,
    frames: u8 = 0,
    rate: TimecodeRate,
    is_drop_frame: bool = false,

    /// Create a validated Timecode.
    pub fn init(
        hours: u8,
        minutes: u8,
        seconds: u8,
        frames: u8,
        rate: TimecodeRate,
        is_drop_frame: bool,
    ) TimecodeError!@This()
    {
        if (hours > 23) return error.hours_out_of_range;
        if (minutes > 59) return error.minutes_out_of_range;
        if (seconds > 59) return error.seconds_out_of_range;
        if (frames >= rate.nominal_fps()) return error.frames_out_of_range;
        if (is_drop_frame and !rate.supports_drop_frame()) {
            return error.drop_frame_not_supported;
        }
        // Check for dropped frame numbers in drop-frame mode
        if (is_drop_frame and seconds == 0 and @mod(minutes, 10) != 0) {
            const drop_count = rate.drop_frames_per_minute();
            if (frames < drop_count) {
                return error.dropped_frame_number;
            }
        }
        return .{
            .hours = hours,
            .minutes = minutes,
            .seconds = seconds,
            .frames = frames,
            .rate = rate,
            .is_drop_frame = is_drop_frame,
        };
    }

    /// Total frame count from midnight.
    pub fn total_frames(
        self: @This(),
    ) i64
    {
        const nominal = @as(i64, self.rate.nominal_fps());
        const frames_per_minute = nominal * 60;
        const frames_per_hour = frames_per_minute * 60;

        var total: i64 = @as(i64, self.hours) * frames_per_hour +
            @as(i64, self.minutes) * frames_per_minute +
            @as(i64, self.seconds) * nominal +
            @as(i64, self.frames);

        if (self.is_drop_frame) {
            const drop_per_min = @as(i64, self.rate.drop_frames_per_minute());
            const total_minutes = @as(i64, self.hours) * 60 + @as(i64, self.minutes);
            // Frames dropped = drop_per_min * (total_minutes - floor(total_minutes/10))
            const drops = drop_per_min * (total_minutes - @divFloor(total_minutes, 10));
            total -= drops;
        }

        return total;
    }
};

/// Validate if a frame rate is a standard SMPTE rate.
pub fn is_valid_smpte_rate(
    rate_hz: f64,
) bool
{
    const rates = [_]f64{
        24000.0 / 1001.0, 24.0, 25.0, 30000.0 / 1001.0, 30.0,
        48000.0 / 1001.0, 48.0, 50.0, 60000.0 / 1001.0, 60.0,
    };
    for (rates) |r| {
        if (@abs(rate_hz - r) < 0.1) return true;
    }
    return false;
}

/// Find nearest SMPTE rate to given frame rate.
pub fn nearest_smpte_rate(
    rate_hz: f64,
) ?TimecodeRate
{
    var min_dist: f64 = std.math.inf(f64);
    var best: ?TimecodeRate = null;
    inline for (std.meta.tags(TimecodeRate)) |rate| {
        const dist = @abs(rate_hz - rate.as_f64());
        if (dist < min_dist and dist < 0.5) {
            min_dist = dist;
            best = rate;
        }
    }
    return best;
}

// ----------------------------------------------------------------------------
// Parsing and Formatting
// ----------------------------------------------------------------------------

/// Parse timecode string to Timecode struct.
/// Accepts "HH:MM:SS:FF" (non-drop-frame) or "HH:MM:SS;FF" (drop-frame).
pub fn from_timecode(
    input: []const u8,
    rate: TimecodeRate,
) TimecodeError!Timecode
{
    if (input.len < 11) return error.invalid_timecode_string;

    // Check for drop-frame separator
    const is_drop_frame = input[8] == ';';
    if (!is_drop_frame and input[8] != ':') {
        return error.invalid_timecode_string;
    }

    // Parse components
    const hours = parse_two_digits(input[0..2]) orelse
        return error.invalid_timecode_string;
    const minutes = parse_two_digits(input[3..5]) orelse
        return error.invalid_timecode_string;
    const seconds = parse_two_digits(input[6..8]) orelse
        return error.invalid_timecode_string;
    const frames = parse_two_digits(input[9..11]) orelse
        return error.invalid_timecode_string;

    // Verify separators
    if (input[2] != ':' or input[5] != ':') {
        return error.invalid_timecode_string;
    }

    return Timecode.init(hours, minutes, seconds, frames, rate, is_drop_frame);
}

/// Parse two ASCII digits to u8.
fn parse_two_digits(
    s: []const u8,
) ?u8
{
    if (s.len != 2) return null;
    const d1 = s[0];
    const d2 = s[1];
    if (d1 < '0' or d1 > '9' or d2 < '0' or d2 > '9') return null;
    return (d1 - '0') * 10 + (d2 - '0');
}

/// Format Timecode to string.
/// Returns "HH:MM:SS:FF" or "HH:MM:SS;FF" based on drop_frame setting.
pub fn to_timecode(
    allocator: std.mem.Allocator,
    tc: Timecode,
) ![]u8
{
    const sep: u8 = if (tc.is_drop_frame) ';' else ':';
    return std.fmt.allocPrint(
        allocator,
        "{d:0>2}:{d:0>2}:{d:0>2}{c}{d:0>2}",
        .{ tc.hours, tc.minutes, tc.seconds, sep, tc.frames },
    );
}

// ----------------------------------------------------------------------------
// Conversion Functions
// ----------------------------------------------------------------------------

/// Convert Timecode to continuous time (Ordinate in seconds).
pub fn timecode_to_ordinate(
    tc: Timecode,
) ordinate.Ordinate
{
    const total = tc.total_frames();
    const fps = tc.rate.as_f64();
    return ordinate.Ordinate.init(@as(f64, @floatFromInt(total)) / fps);
}

/// Convert continuous time to Timecode.
pub fn ordinate_to_timecode(
    ord: ordinate.Ordinate,
    rate: TimecodeRate,
    drop_frame: bool,
) TimecodeError!Timecode
{
    if (ord.v < 0) return error.negative_value;
    if (drop_frame and !rate.supports_drop_frame()) {
        return error.drop_frame_not_supported;
    }

    const fps = rate.as_f64();
    var total_frames: i64 = @intFromFloat(@round(ord.v * fps));

    const nominal: i64 = @as(i64, rate.nominal_fps());
    const frames_per_minute = nominal * 60;
    const frames_per_hour = frames_per_minute * 60;
    const frames_per_day = frames_per_hour * 24;

    // Handle 24-hour rollover
    total_frames = @mod(total_frames, frames_per_day);

    // Add back dropped frames for drop-frame timecode
    if (drop_frame) {
        total_frames = compensate_for_drop_frame(total_frames, rate);
    }

    // Extract components
    const hours: u8 = @intCast(@divFloor(total_frames, frames_per_hour));
    var remaining = @mod(total_frames, frames_per_hour);
    const minutes: u8 = @intCast(@divFloor(remaining, frames_per_minute));
    remaining = @mod(remaining, frames_per_minute);
    const seconds: u8 = @intCast(@divFloor(remaining, nominal));
    const frames: u8 = @intCast(@mod(remaining, nominal));

    return Timecode.init(hours, minutes, seconds, frames, rate, drop_frame);
}

/// Compensate frame count for drop-frame display.
fn compensate_for_drop_frame(
    frame_number: i64,
    rate: TimecodeRate,
) i64
{
    const drop_per_min: i64 = @as(i64, rate.drop_frames_per_minute());
    const nominal: i64 = @as(i64, rate.nominal_fps());
    const frames_per_minute = nominal * 60;

    // Frames per 10-minute block (accounting for drops)
    const frames_per_10min = frames_per_minute * 10 - drop_per_min * 9;

    // Number of complete 10-minute blocks
    const num_10min_blocks = @divFloor(frame_number, frames_per_10min);

    // Remaining frames after complete 10-minute blocks
    var remaining = @mod(frame_number, frames_per_10min);

    // Frames per minute after the first minute of a 10-min block
    const frames_per_min_after_first = frames_per_minute - drop_per_min;

    // Add drops for complete 10-minute blocks
    var result = frame_number + num_10min_blocks * 9 * drop_per_min;

    // Handle remaining frames within the current 10-minute block
    if (remaining >= frames_per_minute) {
        remaining -= frames_per_minute;
        const additional_minutes = @divFloor(remaining, frames_per_min_after_first);
        result += (additional_minutes + 1) * drop_per_min;
    }

    return result;
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "TimecodeRate: as_f64 values"
{
    try std.testing.expectApproxEqRel(
        @as(f64, 23.976),
        TimecodeRate.rate_23_976.as_f64(),
        0.001,
    );
    try std.testing.expectEqual(@as(f64, 24.0), TimecodeRate.rate_24.as_f64());
    try std.testing.expectEqual(@as(f64, 25.0), TimecodeRate.rate_25.as_f64());
    try std.testing.expectApproxEqRel(
        @as(f64, 29.97),
        TimecodeRate.rate_29_97.as_f64(),
        0.001,
    );
    try std.testing.expectEqual(@as(f64, 30.0), TimecodeRate.rate_30.as_f64());
}

test "TimecodeRate: nominal_fps"
{
    try std.testing.expectEqual(@as(u8, 24), TimecodeRate.rate_23_976.nominal_fps());
    try std.testing.expectEqual(@as(u8, 24), TimecodeRate.rate_24.nominal_fps());
    try std.testing.expectEqual(@as(u8, 30), TimecodeRate.rate_29_97.nominal_fps());
    try std.testing.expectEqual(@as(u8, 60), TimecodeRate.rate_59_94.nominal_fps());
}

test "TimecodeRate: supports_drop_frame"
{
    try std.testing.expect(TimecodeRate.rate_29_97.supports_drop_frame());
    try std.testing.expect(TimecodeRate.rate_59_94.supports_drop_frame());
    try std.testing.expect(!TimecodeRate.rate_24.supports_drop_frame());
    try std.testing.expect(!TimecodeRate.rate_30.supports_drop_frame());
}

test "Timecode: basic creation"
{
    const tc = try Timecode.init(1, 23, 45, 12, .rate_24, false);
    try std.testing.expectEqual(@as(u8, 1), tc.hours);
    try std.testing.expectEqual(@as(u8, 23), tc.minutes);
    try std.testing.expectEqual(@as(u8, 45), tc.seconds);
    try std.testing.expectEqual(@as(u8, 12), tc.frames);
}

test "Timecode: validation errors"
{
    try std.testing.expectError(
        error.hours_out_of_range,
        Timecode.init(25, 0, 0, 0, .rate_24, false),
    );
    try std.testing.expectError(
        error.minutes_out_of_range,
        Timecode.init(0, 60, 0, 0, .rate_24, false),
    );
    try std.testing.expectError(
        error.frames_out_of_range,
        Timecode.init(0, 0, 0, 30, .rate_24, false),
    );
    try std.testing.expectError(
        error.drop_frame_not_supported,
        Timecode.init(0, 0, 0, 0, .rate_24, true),
    );
}

test "Timecode: total_frames at 24fps"
{
    const tc = try Timecode.init(0, 0, 1, 12, .rate_24, false);
    try std.testing.expectEqual(@as(i64, 36), tc.total_frames());
}

test "Timecode: total_frames at hour boundary"
{
    const tc = try Timecode.init(1, 0, 0, 0, .rate_24, false);
    try std.testing.expectEqual(@as(i64, 86400), tc.total_frames());
}

test "from_timecode: basic parsing"
{
    const tc = try from_timecode("01:23:45:12", .rate_24);
    try std.testing.expectEqual(@as(u8, 1), tc.hours);
    try std.testing.expectEqual(@as(u8, 23), tc.minutes);
    try std.testing.expectEqual(@as(u8, 45), tc.seconds);
    try std.testing.expectEqual(@as(u8, 12), tc.frames);
    try std.testing.expect(!tc.is_drop_frame);
}

test "from_timecode: drop-frame parsing"
{
    const tc = try from_timecode("01:00:00;02", .rate_29_97);
    try std.testing.expectEqual(@as(u8, 1), tc.hours);
    try std.testing.expectEqual(@as(u8, 0), tc.minutes);
    try std.testing.expectEqual(@as(u8, 0), tc.seconds);
    try std.testing.expectEqual(@as(u8, 2), tc.frames);
    try std.testing.expect(tc.is_drop_frame);
}

test "from_timecode: invalid string"
{
    try std.testing.expectError(
        error.invalid_timecode_string,
        from_timecode("invalid", .rate_24),
    );
    try std.testing.expectError(
        error.invalid_timecode_string,
        from_timecode("01-23-45-12", .rate_24),
    );
}

test "to_timecode: format non-drop-frame"
{
    const allocator = std.testing.allocator;
    const tc = try Timecode.init(1, 23, 45, 12, .rate_24, false);
    const str = try to_timecode(allocator, tc);
    defer allocator.free(str);
    try std.testing.expectEqualStrings("01:23:45:12", str);
}

test "to_timecode: format drop-frame"
{
    const allocator = std.testing.allocator;
    const tc = try Timecode.init(1, 0, 0, 2, .rate_29_97, true);
    const str = try to_timecode(allocator, tc);
    defer allocator.free(str);
    try std.testing.expectEqualStrings("01:00:00;02", str);
}

test "timecode_to_ordinate: basic conversion"
{
    const tc = try Timecode.init(0, 0, 1, 0, .rate_24, false);
    const ord = timecode_to_ordinate(tc);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), ord.v, 0.001);
}

test "ordinate_to_timecode: basic conversion"
{
    const ord = ordinate.Ordinate.init(3661.5);  // 1h 1m 1s + 12 frames
    const tc = try ordinate_to_timecode(ord, .rate_24, false);
    try std.testing.expectEqual(@as(u8, 1), tc.hours);
    try std.testing.expectEqual(@as(u8, 1), tc.minutes);
    try std.testing.expectEqual(@as(u8, 1), tc.seconds);
    try std.testing.expectEqual(@as(u8, 12), tc.frames);
}

test "ordinate_to_timecode: negative value error"
{
    const ord = ordinate.Ordinate.init(-1.0);
    try std.testing.expectError(
        error.negative_value,
        ordinate_to_timecode(ord, .rate_24, false),
    );
}

test "is_valid_smpte_rate"
{
    try std.testing.expect(is_valid_smpte_rate(24.0));
    try std.testing.expect(is_valid_smpte_rate(29.97));
    try std.testing.expect(is_valid_smpte_rate(30.0));
    try std.testing.expect(!is_valid_smpte_rate(15.0));
    try std.testing.expect(!is_valid_smpte_rate(100.0));
}

test "nearest_smpte_rate"
{
    try std.testing.expectEqual(TimecodeRate.rate_24, nearest_smpte_rate(24.0).?);
    try std.testing.expectEqual(TimecodeRate.rate_29_97, nearest_smpte_rate(29.97).?);
    try std.testing.expectEqual(TimecodeRate.rate_30, nearest_smpte_rate(30.0).?);
    try std.testing.expectEqual(null, nearest_smpte_rate(15.0));
}

test "round-trip: string -> timecode -> ordinate -> timecode -> string"
{
    const allocator = std.testing.allocator;
    const original = "01:23:45:12";
    const rate = TimecodeRate.rate_24;

    // Parse
    const tc1 = try from_timecode(original, rate);

    // To ordinate
    const ord = timecode_to_ordinate(tc1);

    // Back to timecode
    const tc2 = try ordinate_to_timecode(ord, rate, false);

    // To string
    const result = try to_timecode(allocator, tc2);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(original, result);
}

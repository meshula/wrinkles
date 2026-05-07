//! Zig bindings for libsamplerate.

pub const SRC_SINC_BEST_QUALITY: c_int = 0;
pub const SRC_SINC_MEDIUM_QUALITY: c_int = 1;
pub const SRC_SINC_FASTEST: c_int = 2;
pub const SRC_ZERO_ORDER_HOLD: c_int = 3;
pub const SRC_LINEAR: c_int = 4;

pub const SRC_STATE = opaque {};

pub const SRC_DATA = extern struct {
    data_in: [*]const f32 = undefined,
    data_out: [*]f32 = undefined,
    input_frames: c_long = 0,
    output_frames: c_long = 0,
    input_frames_used: c_long = 0,
    output_frames_gen: c_long = 0,
    end_of_input: c_int = 0,
    src_ratio: f64 = 0,
};

pub extern fn src_new(
    converter_type: c_int,
    channels: c_int,
    @"error": ?*c_int,
) ?*SRC_STATE;

pub extern fn src_delete(state: ?*SRC_STATE) ?*SRC_STATE;

pub extern fn src_process(state: ?*SRC_STATE, data: *SRC_DATA) c_int;

pub extern fn src_simple(data: *SRC_DATA, converter_type: c_int, channels: c_int) c_int;

pub extern fn src_set_ratio(state: ?*SRC_STATE, new_ratio: f64) c_int;

pub extern fn src_reset(state: ?*SRC_STATE) c_int;

pub extern fn src_error(state: ?*SRC_STATE) c_int;

pub extern fn src_strerror(@"error": c_int) [*:0]const u8;

pub extern fn src_get_name(converter_type: c_int) ?[*:0]const u8;
pub extern fn src_get_description(converter_type: c_int) ?[*:0]const u8;
pub extern fn src_get_version() [*:0]const u8;

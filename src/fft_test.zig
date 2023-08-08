const std = @import("std");

const kiss_fft = @cImport(
    {
        @cInclude("kiss_fft.h");
    }
);


pub fn fft_test() void {
}

pub fn inverse(
    samples: []const std.math.Complex(f32), 
    allocator: std.mem.Allocator,
) ![]std.math.Complex(f32) 
{
    const cfg = kiss_fft.kiss_fft_alloc(
        @intCast(samples.len),
        1,
        null,
        null
    );

    var arg:[]const kiss_fft.kiss_fft_cpx = @ptrCast(samples);

    var result : []kiss_fft.kiss_fft_cpx = try allocator.alloc(
        kiss_fft.kiss_fft_cpx,
        samples.len
    );

    kiss_fft.kiss_fft(
        cfg,
        arg.ptr,
        result.ptr,
    );

    kiss_fft.kiss_fft_free(cfg);

    return @ptrCast(result);
}

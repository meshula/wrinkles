const std = @import("std");

const opentime = @import("opentime");
const otio = @import("opentimelineio");

const Types = union (enum) {
    int,
    f32,
    f64,
    string,
    bool,
    list,
    @"struct",
};

const ziggy = @import("ziggy");

test "ziggy schemas"
{
    const allocator = std.testing.allocator;

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var cl: otio.schema.Clip = .{
        .maybe_name = "Clip-01",
        .maybe_bounds_s = opentime.ContinuousInterval.init(
            .{ .start = 0, .end = 12 }
        ),
        .media = .{
            .domain = .picture,
            .maybe_bounds_s = opentime.ContinuousInterval.init(
                .{ .start = 0, .end = 18 }
            ),
            .maybe_discrete_partition = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 0,
            },
            .data_reference = .{
                .uri = .{
                    .target_uri = "pasta.wav", 
                },
            }
        },
    };

    const cl_ptr = cl.reference();
    var track_children = [_]otio.CompositionItemHandle{ 
        cl_ptr,
    };

    const tr = otio.schema.Track{
        .children = &track_children,
        .maybe_name = "DemoTrack",
    };

    try ziggy.stringify(
        tr,
        .{.whitespace = .space_4},
        &out.writer,
    );

    std.debug.print("result: {s}\n", .{out.written()});

    return error.Barf;
}

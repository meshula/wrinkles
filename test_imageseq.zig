const std = @import("std");
const schema = @import("src/opentimelineio/schema.zig");
const opentime = @import("src/opentime/opentime.zig");

test "MissingFramePolicy: string conversions"
{
    // Test to_string
    try std.testing.expectEqualStrings(
        "error",
        schema.MissingFramePolicy.@"error".to_string()
    );
    try std.testing.expectEqualStrings(
        "hold",
        schema.MissingFramePolicy.hold.to_string()
    );
    try std.testing.expectEqualStrings(
        "black",
        schema.MissingFramePolicy.black.to_string()
    );

    // Test from_string
    try std.testing.expectEqual(
        schema.MissingFramePolicy.@"error",
        schema.MissingFramePolicy.from_string("error").?
    );
    try std.testing.expectEqual(
        schema.MissingFramePolicy.hold,
        schema.MissingFramePolicy.from_string("hold").?
    );
    try std.testing.expectEqual(
        schema.MissingFramePolicy.black,
        schema.MissingFramePolicy.from_string("black").?
    );

    // Test invalid string
    try std.testing.expectEqual(
        null,
        schema.MissingFramePolicy.from_string("invalid")
    );
}

test "ImageSequenceReference: URL generation with no padding"
{
    const allocator = std.testing.allocator;

    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/path/to/frames/",
        .name_prefix = "frame_",
        .name_suffix = ".exr",
        .start_frame = 1,
        .frame_zero_padding = 0,
    };

    const url = try img_seq.target_url_for_image_number(allocator, 42);
    defer allocator.free(url);

    try std.testing.expectEqualStrings(
        "/path/to/frames/frame_42.exr",
        url
    );
}

test "ImageSequenceReference: URL generation with 4-digit padding"
{
    const allocator = std.testing.allocator;

    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/render/",
        .name_prefix = "img_",
        .name_suffix = ".png",
        .start_frame = 1,
        .frame_zero_padding = 4,
    };

    const url1 = try img_seq.target_url_for_image_number(allocator, 1);
    defer allocator.free(url1);
    try std.testing.expectEqualStrings("/render/img_0001.png", url1);

    const url42 = try img_seq.target_url_for_image_number(allocator, 42);
    defer allocator.free(url42);
    try std.testing.expectEqualStrings("/render/img_0042.png", url42);

    const url1000 = try img_seq.target_url_for_image_number(allocator, 1000);
    defer allocator.free(url1000);
    try std.testing.expectEqualStrings("/render/img_1000.png", url1000);
}

test "ImageSequenceReference: URL generation with 6-digit padding"
{
    const allocator = std.testing.allocator;

    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/vfx/",
        .name_prefix = "",
        .name_suffix = ".dpx",
        .start_frame = 1,
        .frame_zero_padding = 6,
    };

    const url = try img_seq.target_url_for_image_number(allocator, 123);
    defer allocator.free(url);
    try std.testing.expectEqualStrings("/vfx/000123.dpx", url);
}

test "ImageSequenceReference: negative start frame"
{
    const allocator = std.testing.allocator;

    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/frames/",
        .name_prefix = "frame.",
        .name_suffix = ".jpg",
        .start_frame = -10,
        .frame_zero_padding = 0,
    };

    const url = try img_seq.target_url_for_image_number(allocator, -5);
    defer allocator.free(url);
    try std.testing.expectEqualStrings("/frames/frame.-5.jpg", url);
}

test "ImageSequenceReference: frame stepping"
{
    const allocator = std.testing.allocator;

    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/seq/",
        .name_prefix = "f",
        .name_suffix = ".tif",
        .start_frame = 10,
        .frame_step = 2,  // Every other frame
        .frame_zero_padding = 3,
    };

    // Frame at time 0
    const url1 = try img_seq.target_url_for_image_number(allocator, 10);
    defer allocator.free(url1);
    try std.testing.expectEqualStrings("/seq/f010.tif", url1);

    // Frame at time that would be frame 2 (step of 2)
    const url2 = try img_seq.target_url_for_image_number(allocator, 12);
    defer allocator.free(url2);
    try std.testing.expectEqualStrings("/seq/f012.tif", url2);
}

test "ImageSequenceReference: frame_for_time calculations"
{
    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 100,
        .frame_step = 1,
        .rate = 24.0,
    };

    // At time 0, should be start_frame
    try std.testing.expectEqual(
        @as(i32, 100),
        img_seq.frame_for_time(opentime.Ordinate.init(0.0))
    );

    // At 1 second (24 frames at 24fps)
    try std.testing.expectEqual(
        @as(i32, 124),
        img_seq.frame_for_time(opentime.Ordinate.init(1.0))
    );

    // At 0.5 seconds (12 frames at 24fps)
    try std.testing.expectEqual(
        @as(i32, 112),
        img_seq.frame_for_time(opentime.Ordinate.init(0.5))
    );
}

test "ImageSequenceReference: frame_for_time with step"
{
    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 1,
        .frame_step = 2,
        .rate = 24.0,
    };

    // At time 0
    try std.testing.expectEqual(
        @as(i32, 1),
        img_seq.frame_for_time(opentime.Ordinate.init(0.0))
    );

    // At 1 second (24 frames, but stepping by 2)
    try std.testing.expectEqual(
        @as(i32, 49),  // 1 + (24 * 2)
        img_seq.frame_for_time(opentime.Ordinate.init(1.0))
    );
}

test "ImageSequenceReference: number_of_images_in_sequence"
{
    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 1,
        .frame_step = 1,
        .rate = 24.0,
    };

    const range = opentime.ContinuousInterval.init(
        .{ .start = 0.0, .end = 1.0 }
    );

    // 1 second at 24fps = 24 frames
    try std.testing.expectEqual(
        @as(i32, 24),
        img_seq.number_of_images_in_sequence(range)
    );
}

test "ImageSequenceReference: number_of_images with step"
{
    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 1,
        .frame_step = 2,
        .rate = 24.0,
    };

    const range = opentime.ContinuousInterval.init(
        .{ .start = 0.0, .end = 1.0 }
    );

    // 1 second at 24fps, stepping by 2 = 12 images
    try std.testing.expectEqual(
        @as(i32, 12),
        img_seq.number_of_images_in_sequence(range)
    );
}

test "ImageSequenceReference: end_frame calculation"
{
    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 100,
        .frame_step = 1,
        .rate = 24.0,
    };

    const range = opentime.ContinuousInterval.init(
        .{ .start = 0.0, .end = 1.0 }
    );

    // Start at 100, 24 frames, so end at 123
    try std.testing.expectEqual(
        @as(i32, 123),
        img_seq.end_frame(range)
    );
}

test "ImageSequenceReference: end_frame with step"
{
    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 1,
        .frame_step = 5,
        .rate = 30.0,
    };

    const range = opentime.ContinuousInterval.init(
        .{ .start = 0.0, .end = 2.0 }
    );

    // 2 seconds at 30fps = 60 frames
    // Stepping by 5 = 12 images
    // Start at 1, so end at 1 + (11 * 5) = 56
    try std.testing.expectEqual(
        @as(i32, 56),
        img_seq.end_frame(range)
    );
}

test "ImageSequenceReference: complete workflow"
{
    const allocator = std.testing.allocator;

    const img_seq = schema.ImageSequenceReference{
        .target_url_base = "/project/renders/",
        .name_prefix = "shot_010_",
        .name_suffix = ".exr",
        .start_frame = 1001,
        .frame_step = 1,
        .frame_zero_padding = 4,
        .rate = 24.0,
        .missing_frame_policy = .hold,
    };

    // Test policy
    try std.testing.expectEqual(
        schema.MissingFramePolicy.hold,
        img_seq.missing_frame_policy
    );

    // Test frame at specific time
    const frame_at_1sec = img_seq.frame_for_time(
        opentime.Ordinate.init(1.0)
    );
    try std.testing.expectEqual(@as(i32, 1025), frame_at_1sec);

    // Test URL generation for that frame
    const url = try img_seq.target_url_for_image_number(
        allocator,
        frame_at_1sec
    );
    defer allocator.free(url);
    try std.testing.expectEqualStrings(
        "/project/renders/shot_010_1025.exr",
        url
    );

    // Test sequence calculations
    const range = opentime.ContinuousInterval.init(
        .{ .start = 0.0, .end = 5.0 }
    );
    const num_images = img_seq.number_of_images_in_sequence(range);
    try std.testing.expectEqual(@as(i32, 120), num_images);

    const last_frame = img_seq.end_frame(range);
    try std.testing.expectEqual(@as(i32, 1120), last_frame);
}

//! MappingCurveBezier / OpenTimelineIO
//!
//! Bezier Curve Mapping wrapper around the curve library

const std = @import("std");

const curve = @import("curve");
const opentime = @import("opentime");
const mapping_mod = @import("mapping.zig");

const topology = @import("topology.zig");

/// a Cubic Bezier Mapping from input to output
pub const MappingCurveBezier = struct {
    input_to_output_curve: curve.Bezier,

    pub fn init_curve(
        allocator: std.mem.Allocator,
        crv: curve.Bezier,
    ) !topology.TopologyMapping
    {
        var result_mappings = (
            std.ArrayList(mapping_mod.Mapping).init(allocator)
        );
        defer result_mappings.deinit();

        const lin = try crv.linearized(allocator);
        defer lin.deinit(allocator);

        const lin_split = try lin.split_at_critical_points(
            allocator
        );
        defer allocator.free(lin_split);

        for (lin_split)
            |mono_lin|
        {
            const map_mono =(
                mapping_mod.MappingCurveLinearMonotonic{
                    .input_to_output_curve = mono_lin,
                }
            );

            try result_mappings.append(map_mono.mapping());
        }

        return try topology.TopologyMapping.init(
            allocator,
            result_mappings.items,
        );
    }

    pub fn init_segments(
        allocator: std.mem.Allocator,
        segments: []const curve.Bezier.Segment,
    ) !topology.TopologyMapping
    {
        const crv = try curve.Bezier.init(
            allocator,
            segments
        );
        defer crv.deinit(allocator);

        return try MappingCurveBezier.init_curve(
            allocator,
            crv
        );
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        self.input_to_output_curve.deinit(allocator);
    }

    /// /// project an instantaneous ordinate from the input space to the output
    /// /// space
    /// pub fn project_instantaneous_cc(
    ///     self: @This(),
    ///     ord: opentime.Ordinate,
    /// ) !opentime.Ordinate 
    /// {
    ///     return try self.input_to_output_curve.output_at_input(ord);
    /// }
    ///
    /// /// fetch (computing if necessary) the input bounds of the mapping
    /// pub fn input_bounds(
    ///     self: @This(),
    /// ) opentime.ContinuousTimeInterval
    /// {
    ///     return self.input_to_output_curve.extents_input();
    /// }
    ///
    /// /// fetch (computing if necessary) the output bounds of the mapping
    /// pub fn output_bounds(
    ///     self: @This(),
    /// ) opentime.ContinuousTimeInterval
    /// {
    ///     return self.input_to_output_curve.extents_output();
    /// }

    // pub fn mapping(
    //     self: @This(),
    // ) mapping_mod.Mapping
    // {
    //     return .{
    //         .linear = self,
    //     };
    // }

    pub fn linearized(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !mapping_mod.MappingCurveLinearMonotonic
    {
        return .{ 
            .input_to_output_curve = (
                try self.input_to_output_curve.linearized(allocator)
            ),
        };
    }
};

    // pub fn clone(
    //     self: @This(),
    //     allocator: std.mem.Allocator,
    // ) !MappingCurveBezier
    // {
    //     return .{
    //         .input_to_output_curve = (
    //             try self.input_to_output_curve.clone(allocator)
    //         ),
    //     };
    // }

//     pub fn split_at_input_point(
//         self: @This(),
//         allocator: std.mem.Allocator,
//         pt_input: opentime.Ordinate,
//     ) ![2]mapping_mod.Mapping
//     {
//         const start_segments = self.input_to_output_curve.segments;
//
//         const segment_to_split_ind = (
//             self.input_to_output_curve.find_segment_index(pt_input)
//         ) orelse return error.NoSegmentToSplit;
//         const segment_to_split = start_segments[segment_to_split_ind];
//         const split_segments = segment_to_split.split_at(
//             segment_to_split.findU_input(pt_input)
//         ).?;
//
//         var left_segments = (
//             std.ArrayList(curve.Bezier.Segment).init(allocator)
//         );
//
//         if (segment_to_split_ind > 0) {
//             try left_segments.appendSlice(
//                 start_segments[0..segment_to_split_ind]
//             );
//         }
//
//         try left_segments.append(split_segments[0]);
//
//         var right_segments = (
//             std.ArrayList(curve.Bezier.Segment).init(allocator)
//         );
//         try right_segments.append(split_segments[1]);
//
//         if (segment_to_split_ind < start_segments.len - 1) {
//             try right_segments.appendSlice(
//                 start_segments[segment_to_split_ind..]
//             );
//         }
//
//         return .{
//             .{
//                 .bezier = .{
//                     .input_to_output_curve = .{
//                         .segments = try left_segments.toOwnedSlice(),
//                     },
//                 },
//             },
//             .{
//                 .bezier = .{
//                     .input_to_output_curve = .{
//                         .segments = try right_segments.toOwnedSlice(),
//                     },
//                 },
//             },
//         };
//     }
//
//     pub fn split_at_input_points(
//         self: @This(),
//         allocator: std.mem.Allocator,
//         /// assumes that input points is sorted in the input domain
//         input_points: []const opentime.Ordinate,
//     ) ![]mapping_mod.Mapping
//     {
//         const start_segments = self.input_to_output_curve.segments;
//         const last_segment = start_segments[start_segments.len - 1];
//
//         var input_pt_cursor:usize = 0;
//         var segment_cursor:usize = 0;
//
//         var new_segments = (
//             std.ArrayList(curve.Bezier.Segment).init(allocator)
//         );
//
//         // trim any points that are before the first segment
//         for (input_points, 0..)
//             |pt, pt_ind|
//         {
//             if (
//                 pt > start_segments[0].p0.in 
//                 and pt < last_segment.p3.in
//             )
//             {
//                 input_pt_cursor = pt_ind;
//                 break;
//             }
//         }
//
//         while (
//             input_pt_cursor != input_points.len
//             and segment_cursor != start_segments.len
//         )
//         {
//             const input_pt = input_points[input_pt_cursor];
//             const seg_current = start_segments[segment_cursor];
//
//             if (input_pt > last_segment.p3.in)
//             {
//                 input_pt_cursor = input_points.len;
//                 break;
//             }
//
//             if (input_pt > seg_current.p3.in)
//             {
//                 try new_segments.append(seg_current);
//                 segment_cursor += 1;
//             }
//             if (input_pt > seg_current.p0.in)
//             {
//                 const split_segments = seg_current.split_at(
//                     seg_current.findU_input(input_pt)
//                 ).?;
//
//                 try new_segments.append(&split_segments);
//
//                 input_pt_cursor += 1;
//             }
//             // input_pt == seg_current.p0.in
//             else
//             {
//                 input_pt_cursor += 1;
//             }
//         }
//
//         return .{
//             .{
//                 .bezier = .{
//                     .input_to_output_curve = .{
//                         .segments = try left_segments.toOwnedSlice(),
//                     },
//                 },
//             },
//             .{
//                 .bezier = .{
//                     .input_to_output_curve = .{
//                         .segments = try right_segments.toOwnedSlice(),
//                     },
//                 },
//             },
//         };
//     }
//
//     pub fn shrink_to_output_interval(
//         self: @This(),
//         allocator: std.mem.Allocator,
//         target_output_interval: opentime.ContinuousTimeInterval,
//     ) !MappingCurveBezier
//     {
//         const output_to_input_crv = try curve.inverted(
//             allocator,
//             self.input_to_output_curve
//         );
//         defer output_to_input_crv.deinit(allocator);
//
//         const target_input_interval_as_crv = try (
//             output_to_input_crv.project_affine(
//                 allocator,
//                 opentime.transform.IDENTITY_TRANSFORM,
//                 target_output_interval
//             )
//         );
//         defer target_input_interval_as_crv.deinit(allocator);
//
//         return .{
//             .input_to_output_curve = (
//                 try self.input_to_output_curve.trimmed_in_input_space(
//                     allocator,
//                     target_input_interval_as_crv.extents_input()
//                 )
//             ),
//         };
//     }
//
//     pub fn shrink_to_input_interval(
//         self: @This(),
//         _: std.mem.Allocator,
//         target_output_interval: opentime.ContinuousTimeInterval,
//     ) !MappingCurveBezier
//     {
//         _ = self;
//         _ = target_output_interval;
//         if (true) {
//             return error.NotImplementedBezierShringtoInput;
//         }
//
//         // return .{
//         //     .input_bounds_val = (
//         //         opentime.interval.intersect(
//         //             self.input_bounds_val,
//         //             target_output_interval,
//         //         ) orelse return error.NoOverlap
//         //     ),
//         //     .input_to_output_xform = self.input_to_output_xform,
//         // };
//     }
// };
//
// test "MappingCurveBezier: init and project"
// {
//     const mcb = (
//         try MappingCurveBezier.init_segments(
//             std.testing.allocator, 
//             &.{ 
//                 curve.Bezier.Segment.init_from_start_end(
//                     .{ .in = 0, .out = 0 },
//                     .{ .in = 10, .out = 20 },
//                 ),
//             },
//             )
//     ).mapping();
//     defer mcb.deinit(std.testing.allocator);
//
//     try std.testing.expectEqual(
//         10,  
//         mcb.project_instantaneous_cc(5),
//     );
// }

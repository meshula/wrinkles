//! Time Topology Struct for OpenTime
//! The time topology maps an external temporal coordinate system to an
//! internal one.  Coordinates in the external coordinate system can be
//! projected through the topology to retrieve values in the internal
//! coordinate system.
//!
//! This module implements topogolies for various kinds of transformations, and
//! also conversions and transformations between these types.

const std = @import("std"); 

const opentime = @import("opentime"); 
const interval = opentime.interval;
const transform = opentime.transform;
const util = opentime.util;

const curve = @import("curve"); 

pub const mapping = @import("mapping.zig");
pub const topology = @import("topology.zig");

// import more tests
test 
{
    _ = @import("test_topology_projections.zig");
    _ = topology;
    _ = mapping;
}
//
// // assertions
// const expect = std.testing.expect;
// const expectEqual = std.testing.expectEqual;
// const expectError = std.testing.expectError;
// const expectApproxEqAbs = std.testing.expectApproxEqAbs;
//
// pub const Ordinate = opentime.Ordinate;
//
// const IDENTITY_TRANSFORM = transform.AffineTransform1D{
//     .offset_seconds = 0,
//     .scale = 1,
// };
//
//
// pub const AffineTopology = struct {
//     /// defaults to an infinite identity
//     bounds: interval.ContinuousTimeInterval = interval.INF_CTI,
//     transform: transform.AffineTransform1D =IDENTITY_TRANSFORM, 
//
//     pub fn compute_input_bounds(
//         self: @This(),
//     ) interval.ContinuousTimeInterval 
//     {
//         return self.bounds;
//     }
//
//     pub fn compute_output_bounds(
//         self: @This(),
//     ) interval.ContinuousTimeInterval 
//     {
//         return self.transform.applied_to_bounds(self.bounds);
//     }
//
//     /// if possible, convert the topology to a linear topology with a single
//     /// line segment
//     pub fn linearized(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) !TimeTopology
//     {
//
//         if (self.bounds.is_infinite()) {
//             return error.CannotLinearizeWithInfiniteBounds;
//         }
//
//         const bound_points = [2]curve.ControlPoint{
//             .{
//                 .in = self.bounds.start_seconds,
//                 .out = try self.project_instantaneous_cc(
//                     self.bounds.start_seconds
//                 ),
//             },
//             .{ 
//                 .in = self.bounds.end_seconds,
//                 .out = try self.project_instantaneous_cc(
//                     self.bounds.end_seconds
//                 ),
//             },
//         };
//
//         // clone points into the new Linear
//         return .{
//             .linear_curve = .{
//                 .curve = try curve.Linear.init(
//                     allocator,
//                     &bound_points
//                 )
//             },
//         };
//     }
//
//     pub fn project_instantaneous_cc(
//         self: @This(),
//         ordinate: Ordinate,
//     ) !Ordinate 
//     {
//         if (
//             !self.bounds.overlaps_seconds(ordinate) 
//             // allow projecting the end point
//             and ordinate != self.bounds.end_seconds
//         )
//         {
//             return TimeTopology.ProjectionError.OutOfBounds;
//         }
//
//         return self.transform.applied_to_seconds(ordinate);
//     }
//
//     /// return an inverted version of the affine transformation
//     pub fn inverted(
//         self: @This(),
//     ) !TimeTopology 
//     {
//         var start = self.bounds.start_seconds;
//         if (start != interval.INF_CTI.start_seconds) {
//             start = try self.project_instantaneous_cc(start);
//         }
//         var end = self.bounds.end_seconds;
//         if (end != interval.INF_CTI.end_seconds) {
//             end = self.transform.applied_to_seconds(end);
//         }
//
//         if (start > end) {
//             const tmp = start;
//             start = end;
//             end = tmp;
//         }
//
//         return .{
//             .affine = .{
//                 .bounds = .{ 
//                     .start_seconds = start,
//                     .end_seconds = end 
//                 },
//                 .transform = self.transform.inverted()
//             },
//         };
//     }
//
//     /// project a topology through self (affine transform)
//     ///
//     /// -> means "is projected through"
//     /// A->B (bounds are in A)
//     /// B->C (bounds are in B)
//     /// B->C.project(A->B) => A->C, bounds are in A
//     ///
//     /// self: self.input -> self.output
//     /// other:other.input -> other.output
//     ///
//     /// self.project_topology(other) => other.input -> self.output
//     /// result.bounds -> other.input
//     ///
//     pub fn project_topology(
//         b2c: @This(),
//         allocator: std.mem.Allocator,
//         a2b: TimeTopology,
//         b_bounds_overlap: opentime.ContinuousTimeInterval,
//     ) !TimeTopology 
//     {
//         return switch (a2b) {
//             .bezier_curve => |a2b_bez| .{ 
//                 .bezier_curve = .{
//                     .curve = try curve.join_bez_aff_unbounded(
//                         allocator,
//                         .{
//                             .a2b = a2b_bez.curve,
//                             .b2c = b2c.transform,
//                         },
//                         )
//                 }
//             },
//             .linear_curve => |a2b_lin| 
//             {
//                 var result = try curve.Linear.init(
//                     allocator,
//                     a2b_lin.curve.knots,
//                 );
//                 for (a2b_lin.curve.knots, 0..) 
//                     |knot, knot_index| 
//                     {
//                         result.knots[knot_index] = .{
//                             .in = knot.in,
//                             .out = b2c.transform.applied_to_seconds(knot.out),
//                         };
//                     }
//                 return .{ 
//                     .linear_curve = .{
//                         .curve = result 
//                     }
//                 };
//             },
//             .affine => |a2b_aff| 
//             {
//                 const a2c_xform = (
//                     b2c.transform.applied_to_transform(
//                         a2b_aff.transform
//                     )
//                 );
//
//                 const b2a = a2b_aff.transform.inverted();
//                 const bounds_a = (
//                     b2a.applied_to_bounds(b_bounds_overlap)
//                 );
//
//                 return .{
//                     .affine = .{ 
//                         .bounds = bounds_a,
//                         .transform = a2c_xform,
//                     },
//                 };
//             },
//             .held => |a2b_held| {
//                 if (a2b_held.direction == .ordinate_to_range) {
//                     return .{
//                         .held = .{
//                             .ordinate = a2b_held.ordinate,
//                             .range = (
//                                 b2c.transform.applied_to_bounds(a2b_held.range)
//                             ),
//                             .direction = .ordinate_to_range,
//                         }
//                     };
//                 }
//                 else {
//                     return .{
//                         .held = .{
//                             .ordinate = b2c.transform.applied_to_seconds(
//                                 a2b_held.ordinate
//                             ),
//                             .range = a2b_held.range,
//                             .direction = .ordinate_to_range,
//                         }
//                     };
//                 }
//             },
//             .empty => .{ .empty = .{} },
//         };
//     }
//
//     pub fn clone(
//         self: @This(),
//         _: std.mem.Allocator,
//     ) !TimeTopology
//     {
//         return .{
//             .affine = .{
//                 .bounds = self.bounds,
//                 .transform = self.transform,
//             },
//         };
//     }
//
//     /// custom formatter for std.fmt
//     pub fn format(
//         self: @This(),
//         comptime _: []const u8,
//         _: std.fmt.FormatOptions,
//         writer: anytype,
//     ) !void 
//     {
//         try writer.print(
//             "AffineTopology{{ bounds: {s}, xform: {s} }}",
//             .{
//                 self.bounds,
//                 self.transform,
//             }
//         );
//     }
// };
//
// test "AffineTopology: linearize"
// {
//     const a2b_aff = AffineTopology{
//         .bounds = .{
//             .start_seconds = 0,
//             .end_seconds = 1,
//         },
//         .transform = .{
//             .offset_seconds = 5,
//             .scale = 3,
//         },
//     };
//     const a2b_lin = try a2b_aff.linearized(std.testing.allocator);
//     defer a2b_lin.deinit(std.testing.allocator);
//
//     for (&[_]f32{-1, 0, 0.5, 0.75, 1.0, 2}, 0..)
//         |ord, ind|
//         {
//             errdefer std.debug.print(
//                 "[erroring test: {d}] ord: {d}\n",
//                 .{ ind, ord }
//             );
//             try expectEqual(
//                 a2b_aff.project_instantaneous_cc(ord),
//                 a2b_lin.linear_curve.curve.output_at_input(ord)
//             );
//         }
// }
//
// pub const LinearTopology = struct {
//     curve: curve.Linear,
//
//     pub fn deinit(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) void 
//     {
//         self.curve.deinit(allocator);
//     }
//
//     pub fn compute_input_bounds(
//         self: @This(),
//     ) interval.ContinuousTimeInterval 
//     {
//         const extents = self.curve.extents();
//
//         return .{
//             .start_seconds = extents[0].in,
//             .end_seconds = extents[1].in,
//         };
//     }
//
//     pub fn compute_output_bounds(
//         self: @This(),
//     ) interval.ContinuousTimeInterval 
//     {
//         const extents = self.curve.extents();
//
//         return .{
//             .start_seconds = extents[0].out,
//             .end_seconds = extents[1].out,
//         };
//     }
//
//     pub fn project_instantaneous_cc(
//         self: @This(),
//         ordinate: Ordinate,
//     ) !Ordinate 
//     {
//         return self.curve.output_at_input(ordinate);
//     }
//
//     pub fn inverted(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) !TimeTopology 
//     {
//         const result = TimeTopology{
//             .linear_curve = .{
//                 .curve = try curve.inverted_linear(
//                     allocator,
//                     self.curve
//                 )
//             }
//         };
//         return result;
//     }
//
//     // @TODO: needs to return a list of topologies (imagine a line projected
//     //        through a u)
//
//     /// If self maps B->C, and xform maps A->B, then the result of
//     /// self.project_affine(xform) will map A->C
//     pub fn project_topology(
//         b2c: @This(),
//         allocator: std.mem.Allocator,
//         a2b: TimeTopology,
//         b_bounds_overlap: opentime.ContinuousTimeInterval,
//     ) !TimeTopology 
//     {
//         return switch (a2b) {
//             .affine => |a2b_aff| {
//                 return .{
//                     .linear_curve = .{ 
//                         .curve = try b2c.curve.project_affine(
//                             allocator,
//                             a2b_aff.transform,
//                             // transform "a" bounds to "b" bounds
//                             a2b_aff.transform.applied_to_cti(a2b_aff.bounds),
//                         ) 
//                     }
//                 };
//             },
//             .bezier_curve => |a2b_bez| .{
//                 .linear_curve = .{
//                     .curve = (
//                         try b2c.curve.project_curve(
//                             allocator,
//                             try a2b_bez.curve.linearized(
//                                 allocator
//                             )
//                         )
//                     )[0]
//                 }
//             },
//             .linear_curve => |a2b_lin| .{
//                 .linear_curve = .{ 
//                     .curve = try b2c.curve.project_curve_single_result(
//                         allocator,
//                         a2b_lin.curve
//                     ),
//                 }
//             },
//             .held => |a2b_held| (
//                 if (a2b_held.direction == .ordinate_to_range) .{
//                     .held = .{
//                         .ordinate = a2b_held.ordinate,
//                         .range = (
//                             try b2c.project_topology(
//                                 allocator,
//                                 TimeTopology.init_affine(
//                                     .{ .bounds = b_bounds_overlap }
//                                 ),
//                                 b_bounds_overlap,
//                             )
//                         ).output_bounds(),
//                         .direction = .ordinate_to_range,
//                     },
//                     } 
//                     else .{
//                         .held = .{
//                             .ordinate = try b2c.project_instantaneous_cc(a2b_held.ordinate),
//                             .range = b_bounds_overlap,
//                             .direction = .range_to_ordinate,
//                         },
//                     }
//             ),
//             .empty => .{ .empty = EmptyTopology{} },
//         };
//     }
//
//     pub fn linearized(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) !TimeTopology
//     {
//         return .{ 
//             .linear_curve = .{
//                 .curve = try self.curve.clone(allocator)
//             },
//         };
//     }
//
//     pub fn clone(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) !TimeTopology
//     {
//         return .{
//             .linear_curve = .{
//                 .curve = try self.curve.clone(allocator),
//             },
//         };
//     }
//
//     /// custom formatter
//     pub fn format(
//         self: @This(),
//         comptime _: []const u8,
//         _: std.fmt.FormatOptions,
//         writer: anytype,
//     ) !void 
//     {
//         try writer.print(
//             "LinearTopo{{ self.knots.len: {d} }}",
//             .{
//                 self.curve.knots.len,
//             }
//         );
//     }
// };
//
// test "LinearTopology: invert" 
// {
//     const crv = try curve.Linear.init(
//         std.testing.allocator,
//         &.{ 
//             .{ .in = 0, .out = 10 },
//             .{ .in = 10, .out = 20 },
//         },
//         );
//     defer crv.deinit(std.testing.allocator);
//     const topo = TimeTopology{
//         .linear_curve = .{ .curve = crv }
//     };
//
//     const topo_bounds = topo.input_bounds();
//     try expectEqual(0, topo_bounds.start_seconds);
//     try expectEqual(10, topo_bounds.end_seconds);
//
//     const topo_inv = try topo.inverted(std.testing.allocator);
//     defer topo_inv.deinit(std.testing.allocator);
//     const topo_inv_bounds = topo_inv.input_bounds();
//     try expectEqual(10, topo_inv_bounds.start_seconds);
//     try expectEqual(20, topo_inv_bounds.end_seconds);
//
// }
//
// pub const BezierTopology = struct {
//     curve: curve.Bezier,
//
//     pub fn deinit(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) void 
//     {
//         self.curve.deinit(allocator);
//     }
//
//     pub fn compute_input_bounds(
//         self: @This()
//     ) interval.ContinuousTimeInterval 
//     {
//         const extents = self.curve.extents();
//
//         return .{
//             .start_seconds = extents[0].in,
//             .end_seconds = extents[1].in,
//         };
//     }
//
//     pub fn compute_output_bounds(
//         self: @This()
//     ) interval.ContinuousTimeInterval 
//     {
//         const extents = self.curve.extents();
//
//         return .{
//             .start_seconds = extents[0].out,
//             .end_seconds = extents[1].out,
//         };
//     }
//
//     pub fn project_instantaneous_cc(
//         self: @This(),
//         ordinate: Ordinate,
//     ) !Ordinate 
//     {
//         return self.curve.output_at_input(ordinate);
//     }
//
//     pub fn inverted(
//         self: @This(),
//         allocator: std.mem.Allocator
//     ) !TimeTopology 
//     {
//         return TimeTopology{
//             .linear_curve = .{ 
//                 .curve = try curve.inverted(
//                     allocator,
//                     self.curve
//                 ) 
//             }
//         };
//     }
//
//     // @TODO: needs to return a list of topologies (imagine a line projected
//     //        through a u)
//     pub fn project_topology(
//         b2c: @This(),
//         allocator: std.mem.Allocator,
//         a2b: TimeTopology,
//         b_bounds_overlap: opentime.ContinuousTimeInterval,
//         // @TODO: should fill a list of TimeTopology
//         // out: *std.ArrayList(TimeTopology),
//     ) !TimeTopology 
//     {
//         return switch (a2b) {
//             .affine => |a2b_aff| {
//                 const projected_curve = try b2c.curve.project_affine(
//                     allocator,
//                     a2b_aff.transform,
//                 );
//
//                 return .{
//                     .bezier_curve = .{ 
//                         .curve = projected_curve,
//                     },
//                 };
//             },
//             .bezier_curve => |a2b_bez| switch (
//                 curve.bezier_curve.project_algo
//             ) {
//                 .three_point_approx, .two_point_approx => .{
//                     .bezier_curve = .{
//                         .curve = try b2c.curve.project_curve(
//                             allocator,
//                             a2b_bez.curve,
//                         )
//                     }
//                 },
//                 .linearized => .{ 
//                     .linear_curve = .{
//                         .curve = (
//                             try (
//                                 try b2c.curve.linearized(
//                                     allocator,
//                                 )
//                             ).project_curve(
//                             allocator,
//                             lc:{
//                                 const result = (
//                                     try a2b_bez.curve.linearized(allocator)
//                                 );
//                                 defer result.deinit(allocator);
//                                 break:lc result;
//                             },
//                             )
//                         )[0]
//                     }
//                 },
//                 },
//             .linear_curve => |a2b_lin| .{
//                 .linear_curve = .{
//                     .curve = (
//                         try (
//                             lc:{
//                                 const result = (
//                                     try b2c.curve.linearized(allocator)
//                                 );
//                                 defer result.deinit(allocator);
//                                 break:lc result;
//                             }
//                         ).project_curve(
//                         allocator,
//                         a2b_lin.curve,
//                         )
//                     )[0]
//                 }
//             },
//             .empty => .{
//                 .empty = EmptyTopology{} 
//             },
//             .held => |a2b_held| (
//                 if (a2b_held.direction == .ordinate_to_range) .{
//                     .held = .{
//                         .ordinate = a2b_held.ordinate,
//                         .range = (
//                             try b2c.project_topology(
//                                 allocator,
//                                 TimeTopology.init_affine(
//                                     .{ .bounds = b_bounds_overlap }
//                                 ),
//                                 b_bounds_overlap,
//                             )
//                         ).output_bounds(),
//                         .direction = .ordinate_to_range,
//                     },
//                     } 
//                     else .{
//                         .held = .{
//                             .ordinate = try b2c.project_instantaneous_cc(a2b_held.ordinate),
//                             .range = b_bounds_overlap,
//                             .direction = .range_to_ordinate,
//                         },
//                     }
//             ),
//         };
//     }
//
//     pub fn linearized(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) !TimeTopology
//     {
//         return .{
//             .linear_curve = .{ 
//                 .curve = try self.curve.linearized(allocator),
//             },
//         };
//     }
//
//     pub fn clone(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) !TimeTopology
//     {
//         return .{
//             .bezier_curve = .{
//                 .curve = try self.curve.clone(allocator),
//             },
//         };
//     }
//
//     /// custom formatter for std.fmt
//     pub fn format(
//         self: @This(),
//         comptime _: []const u8,
//         _: std.fmt.FormatOptions,
//         writer: anytype,
//     ) !void 
//     {
//         try writer.print(
//             "BezTopo{{ segments.len: {d} }}",
//             .{
//                 self.curve.segments.len,
//             }
//         );
//     }
// };
//
// test "BezierTopology: inverted" 
// {
//     const base_curve = try curve.read_curve_json(
//         "curves/scurve.curve.json",
//         std.testing.allocator,
//     );
//     defer base_curve.deinit(std.testing.allocator);
//
//     // this curve is [-0.5, 0.5), rescale it into test range
//     const xform_curve = try curve.rescaled_curve(
//         std.testing.allocator,
//         base_curve,
//         //  the range of the clip for testing - rescale factors
//         .{
//             .{ .in = 100, .out = 0, },
//             .{ .in = 110, .out = 10, },
//         }
//     );
//     defer xform_curve.deinit(std.testing.allocator);
//     const curve_topo = TimeTopology.init_bezier_cubic(
//         xform_curve
//     );
//     const curve_topo_bounds = curve_topo.input_bounds();
//     try expectEqual(100, curve_topo_bounds.start_seconds);
//     try expectEqual(110, curve_topo_bounds.end_seconds);
//
//     const curve_topo_inverted = try curve_topo.inverted(
//         std.testing.allocator
//     );
//     defer curve_topo_inverted.deinit(std.testing.allocator);
//     const topo_inv_bounds = curve_topo_inverted.input_bounds();
//     try expectEqual(0, topo_inv_bounds.start_seconds);
//     try expectEqual(10, topo_inv_bounds.end_seconds);
// }
//
// pub const EmptyTopology = struct {
//     pub fn project_instantaneous_cc(_: @This(), _: Ordinate) !Ordinate {
//         return error.OutOfBounds;
//     }
//     pub fn inverted(_: @This()) !TimeTopology {
//         return .{ .empty = .{} };
//     }
//     pub fn compute_input_bounds(_: @This()) interval.ContinuousTimeInterval {
//         return .{ .start_seconds = 0, .end_seconds = 0 };
//     }
//     pub fn compute_output_bounds(_: @This()) interval.ContinuousTimeInterval {
//         return .{ .start_seconds = 0, .end_seconds = 0 };
//     }
//
//     pub fn clone(
//         _: @This(),
//         _: std.mem.Allocator,
//     ) !TimeTopology
//     {
//         return .{
//             .empty = .{},
//         };
//     }
//
//     /// custom formatter for std.fmt
//     pub fn format(
//         _: @This(),
//         comptime _: []const u8,
//         _: std.fmt.FormatOptions,
//         writer: anytype,
//     ) !void 
//     {
//         try writer.print( "EmptyTopo{{}}", .{});
//     }
//
//
// };
//
// /// A mapping either from an ordinate to a range or from a range to an
// /// ordinate.  An enum (direction) determines which.
// const RangeToOrdinateTopology = struct {
//     ordinate: opentime.Ordinate,
//     range: opentime.ContinuousTimeInterval,
//     direction : MappingKind,
//
//     /// indicates whether the mapping has been inverted or not
//     const MappingKind = enum {
//         /// inverted
//         ordinate_to_range,
//         /// forward
//         range_to_ordinate,
//     };
//
//     pub fn clone(
//         self: @This(),
//         _: std.mem.Allocator,
//     ) !TimeTopology
//     {
//         return .{
//             .held = .{
//                 .ordinate = self.ordinate,
//                 .range = self.range,
//                 .direction = self.direction,
//             },
//         };
//     }
//
//     pub fn project_instantaneous_cc(
//         self: @This(),
//         ord_in_input_space:Ordinate,
//     ) !Ordinate 
//     {
//         if (
//             self.direction == .range_to_ordinate
//             and (self.range.overlaps_seconds(ord_in_input_space))
//         )
//         {
//             return self.ordinate;
//         }
//         else
//         {
//             // point to range
//             return error.OutOfBounds;
//         }
//     }
//
//     pub fn inverted(
//         self: @This(),
//         _: std.mem.Allocator,
//     ) !TimeTopology 
//     {
//         return .{
//             .held = .{
//                 .ordinate = self.ordinate,
//                 .range = self.range,
//                 .direction = (
//                     if (self.direction == .ordinate_to_range) .range_to_ordinate 
//                     else .ordinate_to_range
//                 ),
//             },
//         };
//     }
//
//     pub fn compute_input_bounds(
//         self: @This(),
//     ) interval.ContinuousTimeInterval 
//     {
//         if (self.direction == .ordinate_to_range) 
//         {
//             return .{ 
//                 .start_seconds = self.ordinate,
//                 .end_seconds = self.ordinate,
//             };
//         }
//         else {
//             return self.range;
//         }
//     }
//
//     pub fn compute_output_bounds(
//         self: @This(),
//     ) interval.ContinuousTimeInterval 
//     {
//         if (self.direction == .range_to_ordinate) 
//         {
//             return .{ 
//                 .start_seconds = self.ordinate,
//                 .end_seconds = self.ordinate,
//             };
//         }
//         else {
//             return self.range;
//         }
//     }
//
//     pub fn deinit(
//         _: @This(),
//         _: std.mem.Allocator,
//     ) void 
//     {
//     }
//
//     pub fn format(
//         self: @This(),
//         comptime _: []const u8,
//         _: std.fmt.FormatOptions,
//         writer: anytype,
//     ) !void 
//     {
//         try writer.print(
//             "Held ({any}) {{ ordinate: {d}, range: {s}, }}",
//             .{
//                 self.direction,
//                 self.ordinate,
//                 self.range,
//             }
//         );
//     }
//
//     pub fn project_topology(
//         b2c: @This(),
//         _: std.mem.Allocator,
//         _: TimeTopology,
//         b_bounds_overlap: opentime.ContinuousTimeInterval,
//     ) !TimeTopology 
//     {
//         if (b2c.direction == .range_to_ordinate)
//         {
//             return .{
//                 .held = .{
//                     .ordinate = b2c.ordinate,
//                     .range = b_bounds_overlap,
//                     .direction = .range_to_ordinate,
//                 },
//             };
//         }
//         else 
//         {
//             return .{
//                 .held = .{
//                     .ordinate = b2c.ordinate,
//                     .range = b2c.range,
//                     .direction = .ordinate_to_range,
//                 },
//             };
//         }
//     }
// };
//
// /// TEMPORAL TOPOLOGY PROTOTYPE V2
// /// ///////////////////////////////////////////////////////////////////////////
// /// The time topology maps an external temporal coordinate system to an
// /// internal one.  Coordinates in the external coordinate system can be
// /// projected through the topology to retrieve values in the internal
// /// coordinate system.
// ///
// /// The time toplogy is a right met piecewise-linear function.
// ///
// ///              0                 36          50 (duration of the bounds)
// /// output       |-----------------*-----------|
// /// internal     |-----------------*-----------|
// ///              100               176         200
// ///
// /// The implementation of this mapping function can be one of a class of 
// /// functions.  This struct maps those functions to the same interface and
// /// handles rules for interoperation between them.
// /// ///////////////////////////////////////////////////////////////////////////
// pub const TimeTopology = union (enum) {
//     affine: AffineTopology,
//     empty: EmptyTopology,
//     held: RangeToOrdinateTopology,
//
//     bezier_curve: BezierTopology,
//     linear_curve: LinearTopology,
//
//     /// initialize an infinite identity topology
//     pub fn init_identity_infinite() TimeTopology {
//         return init_identity(.{});
//     }
//
//     const IdentityArgs = struct {
//         bounds : interval.ContinuousTimeInterval = interval.INF_CTI,
//     };
//
//     ///initialize an identity topology
//     pub fn init_identity(
//         args: IdentityArgs,
//     ) TimeTopology 
//     {
//         return .{
//             .affine = .{
//                 .bounds = args.bounds 
//             } 
//         };
//     }
//
//     /// initialize an affine topology
//     pub fn init_affine(
//         topo: AffineTopology,
//     ) TimeTopology 
//     {
//         return .{ .affine = topo };
//     }
//
//     /// initialize a topology with a single linear curve over [start, end)
//     pub fn init_linear_start_end(
//         start:curve.ControlPoint,
//         end: curve.ControlPoint,
//     ) TimeTopology 
//     {
//         const slope = (end.out - start.out) / (end.in - start.in);
//         if (std.math.isNan(slope) or std.math.isInf(slope)) {
//             @panic("infinite or nan slope");
//         }
//         const offset = start.out - start.in * slope;
//         return init_affine(
//             .{
//                 .bounds = .{
//                     .start_seconds = start.in,
//                     .end_seconds = end.in 
//                 },
//                 .transform = .{
//                     .scale = slope,
//                     .offset_seconds = offset,
//                 }
//             }
//         );
//     }
//
//     /// initialize a topology with the given bezier cubic
//     pub fn init_bezier_cubic(
//         cubic: curve.Bezier,
//     ) TimeTopology 
//     {
//         return .{
//             .bezier_curve = .{
//                 .curve = cubic
//             }
//         };
//     }
//
//     /// initialize an empty time topology
//     pub fn init_empty() TimeTopology 
//     {
//         return .{ .empty = EmptyTopology{} };
//     }
//
//     pub fn deinit(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) void 
//     {
//         switch (self) {
//             inline .affine, .empty => {},
//             inline else => |t| t.deinit(allocator),
//         }
//     }
//
//     // @TODO: should include a phase offset
//     /// builds a TimeTopology out with a mapping that contains a step function
//     pub fn init_step_mapping(
//         allocator: std.mem.Allocator,
//         in_bounds: interval.ContinuousTimeInterval,
//         /// the value of the function at the initial sample (f(0))
//         start_value: f32,
//         /// lenght of each step
//         held_duration: f32,
//         /// distance between each step
//         increment: f32,
//     ) !TimeTopology
//     {
//         var segments = std.ArrayList(curve.Bezier.Segment).init(
//             allocator,
//         );
//         defer segments.deinit();
//
//         var t_seconds = in_bounds.start_seconds;
//         var current_value = start_value;
//
//         while (t_seconds < in_bounds.end_seconds) 
//             : (
//                 {  
//                     t_seconds += held_duration;
//                     current_value += increment; 
//                 }
//             )
//         {
//             try segments.append(
//                 curve.Bezier.Segment.init_from_start_end(
//                     .{
//                         .in = t_seconds,
//                         .out = current_value
//                     },
//                     .{
//                         .in = t_seconds + held_duration,
//                         .out = current_value
//                     }
//                 )
//             );
//         }
//
//         const crv = curve.Bezier{
//             .segments = try segments.toOwnedSlice(),
//         };
//
//         return TimeTopology.init_bezier_cubic(crv);
//     }
//
//     /// return a caller-owned copy of self
//     pub fn clone(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) !TimeTopology
//     {
//         return switch (self) {
//             inline else => |tt| tt.clone(allocator),
//         };
//     }
//
//     /// the bounding interval of the topology in its input space
//     pub fn input_bounds(
//         self: @This(),
//     ) interval.ContinuousTimeInterval 
//     {
//         return switch (self) {
//             inline else => |contained| contained.compute_input_bounds(),
//         };
//     }
//
//     /// the bounding interval of the topology in its output space
//     pub fn output_bounds(
//         self: @This(),
//     ) interval.ContinuousTimeInterval 
//     {
//         return switch (self) {
//             inline else => |contained| contained.compute_output_bounds(),
//         };
//     }
//
//     // @{ Projections
//     pub fn project_instantaneous_cc(
//         self: @This(),
//         ordinate_in_input_space:Ordinate,
//     ) !Ordinate 
//     {
//         return switch (self) {
//             inline else => |contained| contained.project_instantaneous_cc(
//                 ordinate_in_input_space
//             ),
//         };
//     }
//
//     /// topology interface for projection
//     pub fn project_topology(
//         b2c: @This(),
//         allocator: std.mem.Allocator,
//         a2b: TimeTopology,
//     ) !TimeTopology 
//     {
//         const self_tag_is_empty = std.meta.activeTag(b2c) == .empty;
//         const other_tag_is_empty = std.meta.activeTag(a2b) == .empty;
//
//         if (self_tag_is_empty or other_tag_is_empty) 
//         {
//             return .{ .empty = .{} };
//         }
//
//         // check boundaries
//         const a2b_b_bounds = a2b.output_bounds();
//         const b2c_b_bounds = b2c.input_bounds();
//
//         if (
//             opentime.interval.intersect(a2b_b_bounds, b2c_b_bounds)
//         ) |b_bounds_overlap|
//         {
//             return switch(b2c) {
//                 .empty => .{ .empty = .{} },
//                 inline else =>|v| v.project_topology(
//                     allocator,
//                     a2b,
//                     b_bounds_overlap
//                 ),
//             };
//         }
//         else {
//             return .{ .empty = .{} };
//         }
//     }
//     // @}
//
//     pub fn inverted(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) !TimeTopology 
//     {
//         return switch (self) {
//             inline .affine, .empty => |aff| try aff.inverted(),
//             inline else => |contained| try contained.inverted(allocator),
//         };
//     }
//
//     pub fn linearized(
//         self: @This(),
//         allocator: std.mem.Allocator,
//     ) !TimeTopology
//     {
//         return switch (self) {
//             .empty => .{
//                 .linear_curve = .{
//                     .curve = curve.Linear{} 
//                 } 
//             },
//             inline else => |t| try t.linearized(allocator)
//         };
//     }
//
//     /// custom formatter for std.fmt
//     pub fn format(
//         self: @This(),
//         comptime fmt: []const u8,
//         options: std.fmt.FormatOptions,
//         writer: anytype,
//     ) !void 
//     {
//         switch (self) {
//             inline else => |t| try t.format(fmt, options, writer),
//         }
//     }
//
//     // @{ ERRORS
//     pub const ProjectionError = error { OutOfBounds };
//     // @}
// };
//
// test "TimeTopology: finite identity test" 
// {
//     const tp = TimeTopology.init_identity(
//         .{
//             .bounds = .{
//                 .start_seconds = 100,
//                 .end_seconds = 103
//             }
//         },
//     );
//
//     try expectEqual(tp.input_bounds().end_seconds, 103);
//
//     // @TODO: this test reveals the question in the end point projection -
//     //        should it be an error or not?
//     //
//     //        See: 103 (index 4) in the test array... was "true" for error for
//     //        a long time, but with the sampling work switched it to false
//
//     const times =           [_]f32 {   99,   100,   101,  102,  103,   104, };
//     const expected_result = [_]f32 {   99,   100,   101,  102,  103,   104, };
//     const err =            [_]bool{ true, false, false, false, false, true, };
//
//     for (times, 0..)
//         |t, index| 
//     {
//         errdefer std.log.err(
//             "[{d}] time: {d} expected: {d} err: {any}",
//             .{index, t, expected_result[index], err[index]}
//         );
//
//         if (err[index]) 
//         {
//             try expectError(
//                 TimeTopology.ProjectionError.OutOfBounds,
//                 tp.project_instantaneous_cc(t),
//             );
//         } 
//         else 
//         {
//             try expectApproxEqAbs(
//                 try tp.project_instantaneous_cc(t),
//                 expected_result[index],
//                 util.EPSILON
//             );
//         }
//     }
// }
//
// test "TimeTopology: finite Affine" 
// {
//     const tp = TimeTopology.init_affine(
//         .{ 
//             .bounds = .{ .start_seconds = 0, .end_seconds = 10 },
//             .transform = .{ .offset_seconds = 10, .scale = 2 },
//         }
//     );
//
//     const TestData = struct {
//         seconds: f32,
//         expected: f32,
//         err: bool,
//     };
//
//     // @TODO: this test reveals the question in the end point projection -
//     //        should it be an error or not?
//     //
//     //        See: 10 (index 4) in the test array... was "true" for error for a
//     //        long time, but with the sampling work switched it to false
//
//     const tests = [_]TestData{
//         .{ .seconds = 0, .expected=10, .err = false },
//         .{ .seconds = 5, .expected=20, .err = false },
//         .{ .seconds = 9, .expected=28, .err = false },
//         .{ .seconds = -1, .expected=-2, .err = true },
//         .{ .seconds = 10, .expected=30, .err = false },
//         .{ .seconds = 100, .expected=200, .err = true },
//     };
//
//     for (tests, 0..) 
//         |t, index| 
//     {
//         errdefer std.log.err(
//             "[{d}] time: {d} expected: {d} err: {any}",
//             .{index, t.seconds, t.expected, t.err}
//         );
//
//         if (t.err) 
//         {
//             try expectError(
//                 TimeTopology.ProjectionError.OutOfBounds,
//                 tp.project_instantaneous_cc(t.seconds),
//             );
//         } 
//         else 
//         {
//             try expectApproxEqAbs(
//                 t.expected,
//                 try tp.project_instantaneous_cc(t.seconds),
//                 util.EPSILON
//             );
//         }
//     }
// }
//
// test "TimeTopology: Affine Projected Through inverted Affine" 
// {
//     const tp = TimeTopology.init_affine(
//         .{ 
//             .bounds = .{ .start_seconds = 0, .end_seconds = 10 },
//             .transform = .{ .offset_seconds = 10, .scale = 2 },
//         }
//     );
//
//     const tp_inv = try tp.inverted(std.testing.allocator);
//
//     const expected_bounds = interval.ContinuousTimeInterval{
//         .start_seconds = 10,
//         .end_seconds = 30
//     };
//     try expectApproxEqAbs(
//         expected_bounds.start_seconds,
//         tp_inv.input_bounds().start_seconds,
//         util.EPSILON
//     );
//     try expectApproxEqAbs(
//         expected_bounds.end_seconds,
//         tp_inv.input_bounds().end_seconds,
//         util.EPSILON
//     );
//
//     // projecting ordinates through both should result in the original argument
//     var time:Ordinate = 0;
//     const end_point = tp.input_bounds().end_seconds;
//     while (time < end_point) 
//         : (time += 0.1) 
//     {
//         const result = try tp_inv.project_instantaneous_cc(
//             try tp.project_instantaneous_cc(time)
//         );
//
//         errdefer std.log.err("time: {any} result: {any}", .{time, result});
//
//         try expectApproxEqAbs(time, result, util.EPSILON);
//     }
// }
//
// test "TimeTopology: Affine Projected Through infinite Affine" 
// {
//     const tp = TimeTopology.init_affine(
//         .{ 
//             .bounds = .{ .start_seconds = 0, .end_seconds = 10 },
//             .transform = .{ .offset_seconds = 10, .scale = 2 },
//         }
//     );
//     const tp_inf = TimeTopology.init_identity_infinite();
//
//
//     const tp_through_tp_inf = try tp_inf.project_topology(
//         std.testing.allocator,
//         tp,
//     );
//
//     const tp_inf_through_tp = try tp.project_topology(
//         std.testing.allocator,
//         tp_inf,
//     );
//
//     const expected_bounds = interval.ContinuousTimeInterval{
//         .start_seconds = 0,
//         .end_seconds = 10
//     };
//
//     try expectApproxEqAbs(
//         expected_bounds.start_seconds,
//         tp_through_tp_inf.input_bounds().start_seconds,
//         util.EPSILON
//     );
//     try expectApproxEqAbs(
//         expected_bounds.start_seconds,
//         tp_inf_through_tp.input_bounds().start_seconds,
//         util.EPSILON
//     );
//
//     try expectApproxEqAbs(
//         expected_bounds.end_seconds,
//         tp_through_tp_inf.input_bounds().end_seconds,
//         util.EPSILON
//     );
//     try expectApproxEqAbs(
//         expected_bounds.end_seconds,
//         tp_inf_through_tp.input_bounds().end_seconds,
//         util.EPSILON
//     );
//
//     // projecting ordinates through both should result in the original argument
//     var time:Ordinate = expected_bounds.start_seconds;
//     const end_point = expected_bounds.end_seconds;
//     while (time < end_point) 
//         : (time += 0.1) 
//     {
//         errdefer std.log.err(
//             "time: {any}\n", 
//             .{time}
//         );
//         const expected = try tp.project_instantaneous_cc(time);
//         const result_inf = (
//             try tp_inf_through_tp.project_instantaneous_cc(time)
//         );
//         const result_tp = (
//             try tp_through_tp_inf.project_instantaneous_cc(time)
//         );
//         errdefer std.log.err(
//             "time: {any} result_tp: {any} result_inf: {any}\n", 
//             .{time, result_tp, result_inf}
//         );
//
//         try expectApproxEqAbs(expected, result_inf, util.EPSILON);
//         try expectApproxEqAbs(expected, result_tp, util.EPSILON);
//     }
// }
//
// test "TimeTopology: Affine through Affine w/ negative scale" 
// {
// //                        start                         end
// //                    in   0                 6           10 (duration of the bounds)
// // output_to_intrinsic     |-----------------*-----------|
// //                    out  10                4           0
// //
// //                         0                             10
// // intrinsic_to_media      |-----------------*-----------|
// //                         90                6           100
// //
//     const output_to_intrinsic = TimeTopology.init_linear_start_end(
//         .{ .in = 0, .out = 10 },
//         .{ .in = 10, .out = 0 },
//     );
//
//     const intrinsic_to_media = TimeTopology.init_linear_start_end(
//         .{ .in = 0, .out = 90 },
//         .{ .in = 10, .out = 100 },
//     );
//
//     const output_to_media = try join(
//         std.testing.allocator,
//         .{
//             .a2b = output_to_intrinsic,
//             .b2c = intrinsic_to_media,
//         },
//     );
//
//     try std.testing.expect(std.meta.activeTag(output_to_media) != .empty);
//
//     const TestData = struct {
//         output_s: f32,
//         media_s: f32,
//         err: bool,
//     };
//
//     // @TODO: this test reveals the question in the end point projection -
//     //        should it be an error or not?
//     //
//     //        See: 10 (index 4) in the test array... was "true" for error for
//     //        a long time, but with the sampling work switched it to false
//
//     const output_to_media_tests = [_]TestData{
//         .{ .output_s = 0, .media_s=100, .err = false },
//         .{ .output_s = 3, .media_s=97, .err = false },
//         .{ .output_s = 6, .media_s=94, .err = false },
//         .{ .output_s = 9, .media_s=91, .err = false },
//         .{ .output_s = 10, .media_s=90, .err = false },
//         .{ .output_s = 11, .media_s=89, .err = true },
//     };
//
//     for (output_to_media_tests, 0..) 
//         |t, index| 
//     {
//         errdefer std.log.err(
//             "[{d}] time: {d} expected: {d} err: {any}",
//             .{index, t.output_s, t.media_s, t.err}
//         );
//
//         if (t.err) 
//         {
//             try expectError(
//                 TimeTopology.ProjectionError.OutOfBounds,
//                 output_to_media.project_instantaneous_cc(t.output_s),
//             );
//         } 
//         else 
//         {
//             try expectApproxEqAbs(
//                 t.media_s,
//                 try output_to_media.project_instantaneous_cc(t.output_s),
//                 util.EPSILON
//             );
//         }
//     }
// }
//
// test "TimeTopology: staircase constructor" 
// {
//     const increment:f32 = 2;
//     const tp = try TimeTopology.init_step_mapping(
//         std.testing.allocator,
//         .{
//             .start_seconds = 10,
//             .end_seconds = 20
//         },
//         0,
//         2,
//         increment
//     );
//     defer tp.deinit(std.testing.allocator);
//
//     try expectEqual(
//         @as(usize, 5),
//         tp.bezier_curve.curve.segments.len
//     );
//
//     var value:f32 = 0;
//     for (tp.bezier_curve.curve.segments) 
//         |seg| 
//     {
//         try expectEqual(value, seg.p0.out);
//         value += increment;
//     }
//
//     // evaluate the curve via the external coordinate system
//     try expectEqual(
//         @as(f32, 20),
//         tp.input_bounds().end_seconds
//     );
//
//     try expectEqual(
//         @as(f32, 8),
//         try tp.project_instantaneous_cc(@as(f32, 19)),
//     );
// }
//
// test "TimeTopology: project bezier through affine" 
// {
//     // affine topology
//     //
//     // input:  [0, 10)
//     // output: [100, 110)
//     //
//     const aff_transform = (
//         transform.AffineTransform1D{
//             .offset_seconds = 100,
//             .scale = 1,
//         }
//     );
//     const aff_input_bounds = .{
//         .start_seconds = 0,
//         .end_seconds = 10,
//     };
//     const affine_topo = (
//         TimeTopology.init_affine(
//             .{
//                 .transform = aff_transform,
//                 .bounds = aff_input_bounds,
//             }
//         )
//     );
//
//     //
//     // Bezier curve
//     //
//     // mapping:
//     // input:  [100, 110)
//     // output: [0,    10)
//     //
//     //   shape: (straight line)
//     //
//     //    |   /
//     //    |  /
//     //    | /
//     //    +------
//     //
//
//     var knots = [_]curve.ControlPoint{
//         .{ .in = 100, .out = 0 },
//         .{ .in = 110, .out = 10 },
//     };
//     const lin_crv = curve.Linear{
//         .knots = &knots,
//     };
//     const crv = try curve.Bezier.init_from_linear_curve(
//         std.testing.allocator,
//         lin_crv,
//     );
//     defer crv.deinit(std.testing.allocator);
//
//     const curve_topo = TimeTopology.init_bezier_cubic(crv);
//
//     // bezier through affine
//     {
//         //
//         // should result in a curve mapping:
//         //
//         // (identity curve, 1 segment)
//         //
//         // [100, 110)
//         // [100, 110)
//         //
//         const result = try affine_topo.project_topology(
//             std.testing.allocator,
//             curve_topo
//         );
//         defer result.deinit(std.testing.allocator);
//
//         try std.testing.expect(std.meta.activeTag(result) != TimeTopology.empty);
//     }
//
//     // affine through bezier
//     {
//         //
//         // should result in a curve mapping:
//         //
//         // (identity curve, 1 segment)
//         //
//         // [0, 10)
//         // [0, 10)
//         //
//         const result = try curve_topo.project_topology(
//             std.testing.allocator,
//             affine_topo,
//         );
//         defer result.deinit(std.testing.allocator);
//
//         try std.testing.expect(std.meta.activeTag(result) != TimeTopology.empty);
//     }
// }
//
// test "TimeTopology: project linear through affine"
// {
//     //
//     // affine topology
//     //
//     // input:  [0, 10)
//     // output: [100, 110)
//     //
//     const aff_transform = (
//         transform.AffineTransform1D{
//             .offset_seconds = 100,
//             .scale = 1,
//         }
//     );
//     const aff_input_bounds = .{
//         .start_seconds = 0,
//         .end_seconds = 10,
//     };
//
//     const affine_topo = (
//         TimeTopology.init_affine(
//             .{
//                 .transform = aff_transform,
//                 .bounds = aff_input_bounds,
//             }
//         )
//     );
//
//     //
//     // Linear curve
//     //
//     // mapping:
//     // input:  [100, 110)
//     // output: [0,    10)
//     //
//     //   shape: (straight line)
//     //
//     //    |   /
//     //    |  /
//     //    | /
//     //    +------
//     //
//
//     var knots = [_]curve.ControlPoint{
//         .{ .in = 100, .out = 0 },
//         .{ .in = 110, .out = 10 },
//     };
//     const crv = curve.Linear{
//         .knots = &knots,
//     };
//     const curve_topo = TimeTopology{
//         .linear_curve = .{ .curve = crv },
//     };
//
//     // linear through affine
//     {
//         //
//         // should result in a curve mapping:
//         //
//         // (identity curve, 1 segment)
//         //
//         // [100, 110)
//         // [100, 110)
//         //
//         const result = try affine_topo.project_topology(
//             std.testing.allocator,
//             curve_topo
//         );
//         defer result.deinit(std.testing.allocator);
//
//         try std.testing.expect(std.meta.activeTag(result) != TimeTopology.empty);
//     }
//
//     // affine through linear
//     {
//         //
//         // should result in a curve mapping:
//         //
//         // (identity curve, 1 segment)
//         //
//         // [0, 10)
//         // [0, 10)
//         //
//         const result = try curve_topo.project_topology(
//             std.testing.allocator,
//             affine_topo,
//         );
//         defer result.deinit(std.testing.allocator);
//
//         try std.testing.expect(std.meta.activeTag(result) != TimeTopology.empty);
//     }
// }
//
// const JoinArgs = struct {
//     /// projects from A to B
//     a2b: TimeTopology,
//     /// projects from B to C
//     b2c: TimeTopology, 
// };
//
// /// takes a topology that projects from space "A" to space "B" and a topology
// /// that projects from space "B" to space "C" and builds a new topology that
// /// projects from space "A" to space "C"
// pub fn join(
//     allocator: std.mem.Allocator,
//     args: JoinArgs,
// ) !TimeTopology
// {
//     // check to see if forcing linearization helps
//     // const a2b = switch (args.a2b) {
//     //     .affine => |a2b_aff| (
//     //         if (a2b_aff.transform.scale == 0)
//     //             try a2b_aff.linearized(allocator)
//     //             else
//     //             try args.a2b.clone(allocator)
//     //     ),
//     //     else => try args.a2b.clone(allocator),
//     // };
//     // defer a2b.deinit(allocator);
//     //
//     // const b2c = switch (args.b2c) {
//     //     .affine => |b2c_aff| (
//     //         if (b2c_aff.transform.scale == 0)
//     //             try b2c_aff.linearized(allocator)
//     //             else
//     //             try args.b2c.clone(allocator)
//     //     ),
//     //     else => try args.b2c.clone(allocator),
//     // };
//     // defer b2c.deinit(allocator);
//
//     return try args.b2c.project_topology(
//         allocator,
//         args.a2b,
//     );
// }
//
// test "TimeTopology: join function"
// {
//     const a2b = TimeTopology.init_affine(
//         .{
//             .transform = .{
//                 .offset_seconds = 4,
//                 .scale = 4.0,
//             }
//         }
//     );
//     const b2c = TimeTopology.init_affine(
//         .{
//             .transform = .{
//                 .offset_seconds = 2,
//                 .scale = 0.5,
//             },
//         }
//     );
//     const a2c = try join(
//         std.testing.allocator, 
//         .{
//             .a2b = a2b,
//             .b2c = b2c,
//         }
//     );
//
//     for (&[_]f32{ 0, 1, 4, 5 })
//         |val_a|
//     {
//         const known = try b2c.project_instantaneous_cc(
//             try a2b.project_instantaneous_cc(val_a)
//         );
//
//         const actual = try a2c.project_instantaneous_cc(val_a);
//
//         try expectApproxEqAbs(
//             known,
//             actual,
//             util.EPSILON,
//         );
//     }
// }
//
// test "TimeTopology: held frame w/ identity"
// {
//     const held_aff = TimeTopology.init_affine(
//         .{
//             .bounds = .{
//                 .start_seconds = 0, 
//                 .end_seconds = 5, 
//             },
//             .transform = .{
//                 .offset_seconds = 7,
//                 .scale = 0,
//             },
//         },
//     );
//
//     const ident = TimeTopology.init_identity_infinite();
//
//     {
//         const a2b = held_aff;
//         const b2c = ident;
//
//         const a2c = try join(
//             std.testing.allocator, 
//             .{
//                 .a2b = a2b,
//                 .b2c = b2c,
//             },
//         );
//
//         std.debug.print("a2b: held b2c: ident\n result: {s}\n", .{ a2c });
//         try std.testing.expect(std.meta.activeTag(a2c) != .empty);
//         //
//         // try std.testing.expect(
//         //     std.math.isNan(a2c.affine.bounds.start_seconds) == false
//         //     and std.math.isNan(a2c.affine.bounds.end_seconds) == false
//         // );
//     }
//
//     {
//         const a2b = ident;
//         const b2c = held_aff;
//
//         const a2c = try join(
//             std.testing.allocator, 
//             .{
//                 .a2b = a2b,
//                 .b2c = b2c,
//             },
//         );
//
//         try std.testing.expect(std.meta.activeTag(a2c) != .empty);
//
//         std.debug.print("a2b: ident b2c: held \n result: {s}\n", .{ a2c });
//     }
// }
//
// // @}

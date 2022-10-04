// const expect = @import("std").testing.expect;
// const expectEqual = @import("std").testing.expectEqual;
//
// const Point3d = struct {
//     x: f64,
//     y: f64,
//     z: f64,
//
//     pub fn from_list(ls: [3] f64) @This() {
//         return @This() { 
//             .x = ls[0],
//             .y = ls[1],
//             .z = ls[2],
//         };
//     }
// };
//
// test "point builder" {
//     const p = Point3d.from_list([3]f64 {0, 1, 2});
//
//     expectEqual(p.x, 0);
//     expectEqual(p.y, 1);
//     expectEqual(p.z, 2);
// }
//
// const Edge = struct {
//     point1_index: u64,
//     point2_index: u64,
//
//     pub fn from_list(ls: [2] f64) Self {
//         return .{ 
//             .point1_index = ls[0],
//             .point2_index = ls[1],
//         };
//     }
// };
//
// const Triangle = struct {
//     points: [3] Point3d,
//     edges: [3] Edge,
// };
//
// const Transform2d = struct {
//     var fields= [16]f64 {
//         0,0,0,0,
//         0,0,0,0,
//         0,0,0,0,
//         0,0,0,0,
//     };
//
//     pub fn Identity() Self {
//         return .{ 
//             .fields = [_]f64 {
//                 1,0,0,0,
//                 0,1,0,0,
//                 0,0,1,0,
//                 1,1,1,1,
//             }
//         };
//     }
// };
//
// const Mesh = struct {
//     xform: Transform2d = Transform2d.Identity(),
//     triangles: []Triangle,
// };
//
// pub fn main() !void {
//     // const t1 = Triangle {
//     //     .points = {
//     //         Point3d.from_list({0, 0, 0}),
//     //         Point3d.from_list({1, 0, 0}),
//     //         Point3d.from_list({0, 1, 0}),
//     //     },
//     //     .edges = {
//     //     },
//     // };
// }

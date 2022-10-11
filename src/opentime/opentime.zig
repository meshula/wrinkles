// 
// Exports for the `opentime` library
//

// string @{
pub const string = @import("string_stuff.zig");
// @}

// interval @{
pub const ContinuousTimeInterval = @import("interval.zig").ContinuousTimeInterval;
// @}

// TimeTopology @{
pub const TimeTopology = @import("time_topology.zig").TimeTopology;
// @}

// Domain @{
pub const Domain = @import("domain.zig").Domain;
// @}

// Curve @{
pub const curve = @import("curve/curve.zig");
// @}

test "all" {
    _ = curve;
}

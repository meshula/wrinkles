//
// Exports for the `opentime` library
//

// string @{
pub const string = @import("string_stuff.zig");
// @}

// interval @{
pub const interval = @import("interval.zig");
pub const ContinuousTimeInterval = interval.ContinuousTimeInterval;
// @}

// TimeTopology @{
pub const time_topology = @import("time_topology.zig");
pub const TimeTopology = time_topology.TimeTopology;
// @}

// Domain @{
pub const Domain = @import("domain.zig").Domain;
// @}

// Curve @{
pub const curve = @import("curve/curve.zig");
// @}

// transform
pub const transform = @import("transform.zig");

test "all" {
    _ = curve;
}

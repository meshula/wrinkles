//! Polymorphic lerp and inverse lerp using comath.

const comath_wrapper = @import("comath_wrapper.zig");
const ordinate = @import("ordinate.zig");

/// Linearly interpolate from `a` to `b` by amount `u`, [0, 1].
///
/// Types must be `comath_wrapper` compatible.
pub fn lerp(
    /// Amount to lerp between endpoints a and b.
    u: anytype,
    a: anytype,
    b: @TypeOf(a),
) @TypeOf(a) 
{
    return comath_wrapper.eval(
        "(a * ((-u) + 1.0)) + (b * u)",
        .{
            .a = a,
            .b = b,
            .u = u,
        }
    );
}

/// Inverse linear interpolation -- compute the `u` for which 
/// `lerp(u, a, b) == v`.
pub fn invlerp(
    /// Value to find the u of.
    v: anytype,
    a: anytype,
    b: @TypeOf(a),
) @TypeOf(a)
{
    if (ordinate.eql(b, a)) {
        return a;
    }
    return comath_wrapper.eval(
        "(v - a)/(b - a)",
        .{
            .v = v,
            .a = a,
            .b = b,
        }
    );
}



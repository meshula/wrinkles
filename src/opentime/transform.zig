//! Implementation of a 1d Affine transformation

const std = @import("std"); 

const ordinate = @import("ordinate.zig");
const interval = @import("interval.zig");
const ContinuousInterval = interval.ContinuousInterval; 

/// AffineTransform1D @{
/// ///////////////////////////////////////////////////////////////////////////
/// Represents a homogenous-coordinates transform matrix of the form:
///     | Scale Offset |
///     |   0     1    | (Implicit)
///
/// Transform order scale then offset, ie y = T(x) = (x * Scale + offset)
/// ///////////////////////////////////////////////////////////////////////////
pub const AffineTransform1D = struct {
    offset: ordinate.Ordinate = ordinate.Ordinate.ZERO,
    scale: ordinate.Ordinate = ordinate.Ordinate.ONE,

    pub const IDENTITY = AffineTransform1D{};

    /// transform the ordinate.  Order is scale and then offset.
    pub fn applied_to_ordinate(
        self: @This(),
        ord: ordinate.Ordinate,
    ) ordinate.Ordinate
    {
        return ordinate.eval(
            "ord * scale + offset",
            .{ .ord = ord, .scale = self.scale, .offset = self.offset }
        );
    }

    /// transform the interval by transforming its endpoints.
    pub fn applied_to_interval(
        self: @This(),
        cint: ContinuousInterval,
    ) ContinuousInterval
    {
        return .{
            .start = self.applied_to_ordinate(cint.start),
            .end = self.applied_to_ordinate(cint.end)
        };
    }

    /// if the scale of the transform is negative, the ends will flip during
    /// projection.  For bounds, this isn't meaningful and can cause problems.
    /// This function makes sure that result.start < result.end
    pub fn applied_to_bounds(
        self: @This(),
        bnds: ContinuousInterval,
    ) ContinuousInterval {
        if (self.scale.lt(0)) {
            return .{
                .start = self.applied_to_ordinate(bnds.end),
                .end = self.applied_to_ordinate(bnds.start),
            };
        }

        return self.applied_to_interval(bnds);
    }

    /// transform the transform
    pub fn applied_to_transform(
        self: @This(),
        rhs: AffineTransform1D,
    ) AffineTransform1D 
    {
        return .{
            .offset = self.applied_to_ordinate(rhs.offset),
            .scale = ordinate.eval(
                "rhs_scale * self_scale",
                .{ .rhs_scale = rhs.scale , .self_scale = self.scale,},
            ),
        };
    }

    /// Return the inverse of this transform.
    ///    ** assumes that scale is non-zero **
    ///
    /// Because the AffineTransform1D is a 2x2 matrix of the form:
    ///     | scale offset |
    ///     |   0     1    |
    ///
    /// The inverse is:
    ///     | 1/scale -offset/scale |
    ///     |   0           1       |
    /// To derive this:
    ///     | A B | * | S O |   | 1 0 |
    ///     | C D |   | 0 1 | = | 0 1 |
    ///     =>
    ///     A*S = 1 => A = 1/S
    ///     A*O + B = 0 => B = -O*A => B = -O/S
    ///     C * S = 0 => C = 0
    ///     C * O + D = 1 => D = 1
    pub fn inverted(
        self: @This(),
    ) AffineTransform1D
    {
        // !! Assumes that scale is not 0
        // if (self.scale == 0) {
        //     return ZeroScaleError;
        // }

        return .{
            .offset = ordinate.eval(
                "(-offset)/scale",
                .{ .offset = self.offset, .scale = self.scale },
            ),
            .scale = ordinate.eval("one/scale",
                .{ .one = ordinate.Ordinate.ONE, .scale = self.scale },
            ),
        };
    }

    /// custom formatter for std.fmt
    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void 
    {
        try writer.print(
            "Aff1D{{ offset: {d} scale: {d} }}",
            .{
                self.offset,
                self.scale,
            }
        );
    }
};

pub const IDENTITY_TRANSFORM = AffineTransform1D{
    .offset = 0,
    .scale = 1,
};

test "AffineTransform1D: offset test" 
{
    const cti = ContinuousInterval.init(
        .{ .start = 10, .end = 20, }
    );

    const xform = AffineTransform1D {
        .offset = ordinate.Ordinate.init(10),
        .scale = ordinate.Ordinate.init(1),
    };

    const result: ContinuousInterval = xform.applied_to_interval(cti);
    
    try std.testing.expectEqual(
        ContinuousInterval.init(
            .{ .start = 20, .end = 30 }
        ),
        result
    );

    try std.testing.expectEqual(
        ordinate.Ordinate.init(10),
        result.duration()
    );

    try std.testing.expectEqual(
        cti.duration(),
        result.duration()
    );

    const result_xform = xform.applied_to_transform(xform);

    try std.testing.expectEqual(
        result_xform,
        AffineTransform1D{
            .offset = ordinate.Ordinate.init(20),
            .scale = ordinate.Ordinate.init(1),
        }
    );
}

test "AffineTransform1D: scale test" 
{
    const cti = ContinuousInterval.init(
        .{ .start = 10, .end = 20, }
    );

    const xform = AffineTransform1D {
        .offset = ordinate.Ordinate.init(10),
        .scale = ordinate.Ordinate.init(2),
    };

    const result = xform.applied_to_interval(cti);

    try std.testing.expectEqual(
        ContinuousInterval.init(
            .{ .start = 30, .end = 50, }
        ),
        result
    );

    try std.testing.expectEqual(
        result.duration(),
        cti.duration().mul(xform.scale),
    );

    const result_xform = xform.applied_to_transform(xform);

    try std.testing.expectEqual(
        AffineTransform1D {
            .offset = ordinate.Ordinate.init(30),
            .scale = ordinate.Ordinate.init(4),
        },
        result_xform,
    );
}

test "AffineTransform1D: invert test" 
{
    const xform = AffineTransform1D {
        .offset = ordinate.Ordinate.init(10),
        .scale = ordinate.Ordinate.init(2),
    };

    const identity = xform.applied_to_transform(
        xform.inverted()
    );

    try std.testing.expectEqual(ordinate.Ordinate.ZERO, identity.offset);
    try std.testing.expectEqual(ordinate.Ordinate.ONE, identity.scale);

    const pt=ordinate.Ordinate.init(10);

    const result = xform.inverted().applied_to_ordinate(
        xform.applied_to_ordinate(pt)
    );

    try std.testing.expectEqual(pt, result);
}

test "AffineTransform1D: applied_to_bounds" 
{
    const xform = AffineTransform1D {
        .offset = ordinate.Ordinate.init(10),
        .scale = ordinate.Ordinate.init(-1),
    };
    const bounds = ContinuousInterval{
        .start = ordinate.Ordinate.init(10),
        .end = ordinate.Ordinate.init(20),
    };
    const result = xform.applied_to_bounds(bounds);

    try std.testing.expect(result.start.lt(result.end));
}

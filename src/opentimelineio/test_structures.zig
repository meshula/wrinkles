
const opentime = @import("opentime");

// TEST STRUCTS
pub const T_INT_1_TO_9 = opentime.ContinuousInterval{
    .start = .one,
    .end = opentime.Ordinate.init(9),
};
pub const T_INT_1_TO_4 = opentime.ContinuousInterval{
    .start = .one,
    .end = opentime.Ordinate.init(4),
};
pub const T_INT_0_TO_2 = opentime.ContinuousInterval{
    .start = .zero,
    .end = opentime.Ordinate.init(2),
};

pub const T_O_0 = opentime.Ordinate.zero;
pub const T_O_2 = opentime.Ordinate.init(2);
pub const T_O_4 = opentime.Ordinate.init(4);
pub const T_O_6 = opentime.Ordinate.init(6);

pub const T_ORD_ARR_0_8_16_21 = [_]opentime.Ordinate{
            .zero,
            opentime.Ordinate.init(8),
            opentime.Ordinate.init(16),
            opentime.Ordinate.init(21),
};
pub const T_ORD_ARR_0_8_13_21 = [_]opentime.Ordinate{
            .zero,
            opentime.Ordinate.init(8),
            opentime.Ordinate.init(13),
            opentime.Ordinate.init(21),
};

pub const T_O_8 = opentime.Ordinate.init(8);
pub const T_O_12 = opentime.Ordinate.init(12);
pub const T_O_20 = opentime.Ordinate.init(20);
pub const T_INTERVAL_ARR_0_8_12_20 = [_]opentime.ContinuousInterval{
    .{ .start = .zero, .end = T_O_8 },
    .{ .start = T_O_8, .end = T_O_12 },
    .{ .start = T_O_12, .end = T_O_20 },
};


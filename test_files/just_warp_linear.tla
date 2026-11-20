.schema_version = 1,
.name = "Linear Curve",
.children = [
    .track(.{
        .name = "Track-001",
        .children = [
            .warp(.{
                .name = "Linear Curve",
                .child = .clip(.{
                    .name = "Clip-001",
                    .bounds_s = .discrete([
                        0,
                        10,
                    ]),
                    .media = .{
                        .data_reference = .uri(.{
                            .target_uri = "file:///folder/titles.mov",
                        }),
                        .bounds_s = .discrete([
                            1,
                            9,
                        ]),
                        .domain = .picture,
                        .discrete_partition = .{
                            .sample_rate_hz = .Integer(1),
                            .start_index = 0,
                        },
                    },
                    .markers = [
                    ],
                }),
                .transform = .{
                    .mappings = [
                        .linear(.{
                            .input_bounds_val = [
                                0,
                                2,
                            ],
                            .knots = [
                                [
                                    0,
                                    0,
                                ],
                                [
                                    1,
                                    1,
                                ],
                                [
                                    1.25,
                                    1.6,
                                ],
                                [
                                    2,
                                    4,
                                ],
                            ],
                        }),
                    ],
                },
            }),
        ],
        .markers = [
        ],
    }),
],
.presentation_space_discrete_partitions = .{},
.markers = [
],

.schema_version = 1,
.name = "Warp Example",
.children = [
    track {
        .name = "Track-001",
        .children = [
            warp {
                .name = "Linear Accel",
                .child = clip {
                    .name = "Clip-001",
                    .bounds_s = discrete [
                        3,
                        6,
                    ],
                    .media = {
                        .data_reference = uri {
                            .target_uri = "file:///folder/titles.mov",
                        },
                        .bounds_s = discrete [
                            0,
                            8,
                        ],
                        .domain = picture {},
                        .discrete_partition = {
                            .sample_rate_hz = Int 24,
                            .start_index = 0,
                        },
                    },
                    .markers = [
                    ],
                },
                .transform = {
                    .mappings = [
                        affine {
                            .input_bounds_val = [
                                -inf,
                                inf,
                            ],
                            .input_to_output_xform = {
                                .offset = -0.041666666666666664,
                                .scale = -0.08333333333333333,
                            },
                        },
                    ],
                },
            },
            clip {
                .name = "Clip-002",
                .bounds_s = discrete [
                    2,
                    8,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/wind-up.mov",
                    },
                    .bounds_s = discrete [
                        0,
                        8,
                    ],
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Int 24,
                        .start_index = 0,
                    },
                },
                .markers = [
                ],
            },
            clip {
                .name = "Clip-003",
                .bounds_s = discrete [
                    0,
                    4,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/punchline.mov",
                    },
                    .bounds_s = discrete [
                        0,
                        8,
                    ],
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Int 24,
                        .start_index = 0,
                    },
                },
                .markers = [
                ],
            },
            clip {
                .name = "Clip-004",
                .bounds_s = continuous [
                    4.166666666666667,
                    4.416666666666667,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/credits.mov",
                    },
                    .bounds_s = continuous [
                        4.166666666666667,
                        4.416666666666667,
                    ],
                    .domain = picture {},
                },
                .markers = [
                ],
            },
        ],
        .markers = [
        ],
    },
],
.presentation_space_discrete_partitions = {},
.markers = [
],

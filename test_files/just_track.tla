.schema_version = 1,
.name = "Track-001",
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
                            .sample_rate_hz = Integer 24,
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
                                .offset = 0.0,
                                .scale = -2.0,
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
                        .sample_rate_hz = Integer 24,
                        .start_index = 0,
                    },
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

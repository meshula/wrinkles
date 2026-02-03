.schema_version = 1,
.name = "-1 Aff",
.children = [
    track {
        .name = "Track-001",
        .children = [
            warp {
                .name = "-1 Aff",
                .child = warp {
                    .name = "2x Aff",
                    .child = clip {
                        .name = "Clip-001",
                        .bounds_s = discrete [
                            0,
                            1,
                        ],
                        .media = {
                            .data_reference = uri {
                                .target_uri = "file:///folder/titles.mov",
                            },
                            .bounds_s = discrete [
                                1,
                                2,
                            ],
                            .domain = picture {},
                            .discrete_partition = {
                                .sample_rate_hz = Integer 1,
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
                                    .scale = 2.0,
                                },
                            },
                        ],
                    },
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
                                .scale = -1.0,
                            },
                        },
                    ],
                },
            },
        ],
        .markers = [
        ],
    },
],
.presentation_space_discrete_partitions = {},
.markers = [
],

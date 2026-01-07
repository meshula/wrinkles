.schema_version = 1,
.name = "Figure 3 - Multiple Tracks",
.children = [
    track {
        .name = "Track-001",
        .children = [
            clip {
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
                        9,
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
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    0.16666666666666666,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "Clip-004",
                .bounds_s = discrete [
                    100,
                    106,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/credits.mov",
                    },
                    .bounds_s = discrete [
                        100,
                        106,
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
        ],
        .markers = [
        ],
    },
    track {
        .name = "Track-002",
        .children = [
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    0.2916666666666667,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "Clip-003",
                .bounds_s = discrete [
                    100,
                    109,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/punchline.mov",
                    },
                    .bounds_s = discrete [
                        100,
                        109,
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
        ],
        .markers = [
        ],
    },
    track {
        .name = "Track-003",
        .children = [
            clip {
                .name = "Clip-005",
                .bounds_s = discrete [
                    100,
                    109,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/punchline.mov",
                    },
                    .bounds_s = discrete [
                        100,
                        109,
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
        ],
        .markers = [
        ],
    },
],
.presentation_space_discrete_partitions = {},
.markers = [
],

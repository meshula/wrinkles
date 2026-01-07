.schema_version = 1,
.name = "tracks",
.children = [
    track {
        .name = "tracks",
        .children = [
            clip {
                .name = "Clip-001",
                .bounds_s = discrete [
                    0,
                    24,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/titles.mov",
                    },
                    .bounds_s = discrete [
                        0,
                        24,
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
            transition {
                .name = "A to B",
                .container = {
                    .name = "tracks",
                    .children = [
                        clip {
                            .name = "Clip-001",
                            .bounds_s = discrete [
                                24,
                                48,
                            ],
                            .media = {
                                .data_reference = uri {
                                    .target_uri = "file:///folder/titles.mov",
                                },
                                .bounds_s = discrete [
                                    0,
                                    48,
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
                                0,
                                24,
                            ],
                            .media = {
                                .data_reference = uri {
                                    .target_uri = "file:///folder/wind-up.mov",
                                },
                                .bounds_s = discrete [
                                    0,
                                    24,
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
                .kind = "Cross Dissolve",
            },
            clip {
                .name = "Clip-002",
                .bounds_s = discrete [
                    24,
                    48,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/wind-up.mov",
                    },
                    .bounds_s = discrete [
                        24,
                        48,
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

.schema_version = 1,
.name = "simple_cut_with_markers",
.children = [
    track {
        .name = "Video Track",
        .children = [
            clip {
                .name = "Clip with Markers",
                .bounds_s = discrete [
                    0,
                    100,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///media/clip1.mov",
                    },
                    .bounds_s = discrete [
                        0,
                        100,
                    ],
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 24,
                        .start_index = 0,
                    },
                },
                .markers = [
                    {
                        .name = "Start Marker",
                        .marked_range = [
                            0.4166666666666667,
                            0.9166666666666667,
                        ],
                        .color = "RED",
                    },
                    {
                        .name = "Mid Point",
                        .marked_range = [
                            2.0833333333333335,
                            2.125,
                        ],
                        .color = "GREEN",
                    },
                ],
            },
            gap {
                .name = "Gap with Marker",
                .bounds_s = [
                    0.0,
                    1.0,
                ],
                .markers = [
                    {
                        .name = "Gap Marker",
                        .marked_range = [
                            0.20833333333333334,
                            0.4166666666666667,
                        ],
                        .color = "BLUE",
                    },
                ],
            },
        ],
        .markers = [
            {
                .name = "Track Marker",
                .marked_range = [
                    2.5,
                    2.9166666666666665,
                ],
                .color = "YELLOW",
            },
        ],
    },
],
.presentation_space_discrete_partitions = {},
.markers = [
],

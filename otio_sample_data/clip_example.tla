.schema_version = 1,
.name = "transition_test",
.children = [
    track {
        .name = "Track-001",
        .children = [
            gap {
                .name = "Gap A",
                .bounds_s = [
                    0.0,
                    0.3333333333333333,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "Clip-001",
                .bounds_s = discrete [
                    3,
                    6,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 24,
                        .start_index = 0,
                    },
                },
                .markers = [
                ],
            },
            transition {
                .name = "Dissolve",
                .container = {
                    .name = "",
                    .children = [
                    ],
                    .markers = [
                    ],
                },
                .kind = "SMPTE_Dissolve",
            },
            gap {
                .name = "Gap B",
                .bounds_s = [
                    0.0,
                    0.3333333333333333,
                ],
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

.schema_version = 1,
.name = "transition_test",
.children = [
    track {
        .name = "Sequence1",
        .children = [
            transition {
                .name = "t0",
                .container = {
                    .children = [
                    ],
                    .markers = [
                    ],
                },
                .kind = "SMPTE_Dissolve",
            },
            clip {
                .name = "A",
                .bounds_s = discrete [
                    0,
                    50,
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
                .name = "t1",
                .container = {
                    .children = [
                    ],
                    .markers = [
                    ],
                },
                .kind = "SMPTE_Dissolve",
            },
            clip {
                .name = "B",
                .bounds_s = discrete [
                    0,
                    50,
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
            clip {
                .name = "C",
                .bounds_s = discrete [
                    0,
                    50,
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
                .name = "t3",
                .container = {
                    .children = [
                    ],
                    .markers = [
                    ],
                },
                .kind = "SMPTE_Dissolve",
            },
        ],
        .markers = [
        ],
    },
],
.presentation_space_discrete_partitions = {},
.markers = [
],

.schema_version = 1,
.name = "Discrete Test Track",
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
.presentation_space_discrete_partitions = {
    .picture = {
        .sample_rate_hz = Integer 24,
        .start_index = 100,
    },
    .audio = {
        .sample_rate_hz = Integer 100,
        .start_index = 0,
    },
},
.markers = [
],

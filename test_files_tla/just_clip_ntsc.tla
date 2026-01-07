.schema_version = 1,
.name = "Clip-001-NTSC",
.children = [
    track {
        .name = "Track-001",
        .children = [
            clip {
                .name = "Clip-001",
                .bounds_s = discrete [
                    0,
                    3,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/titles.mov",
                    },
                    .bounds_s = continuous [
                        0.5,
                        0.8341666666666666,
                    ],
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Rational {
                            .num = 24000,
                            .den = 1001,
                        },
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
        .sample_rate_hz = Rational {
            .num = 24000,
            .den = 1001,
        },
        .start_index = 0,
    },
},
.markers = [
],

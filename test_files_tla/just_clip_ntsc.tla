{
    .schema_version = 1,
    .children = [
        track {
            .name = "Track-001",
            .children = [
                clip {
                    .media = {
                        .data_reference = uri {
                            .target_uri = "file:///folder/titles.mov",
                        },
                        .domain = picture {},
                        .discrete_partition = {
                            .sample_rate_hz = Rational { .num = 24000, .den = 1001 },
                            .start_index = 0,
                        },
                        .bounds_s = continuous [0.5, 0.8341666666666666],
                    },
                    .name = "Clip-001",
                    .bounds_s = discrete [0, 3],
                },
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
    .name = "Clip-001-NTSC",
}

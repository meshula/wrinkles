.schema_version = 1,
.name = "Figure 1 - Simple Cut List With Metadata",
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
                .metadata_hash = "b76b494dd822594b",
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
                        8,
                    ],
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 24,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "04a1ce6df4c0f425",
                .markers = [
                ],
            },
            clip {
                .name = "Clip-003",
                .bounds_s = discrete [
                    0,
                    4,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/punchline.mov",
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
                .metadata_hash = "13fc06cbbe3e2a3e",
                .markers = [
                ],
            },
            clip {
                .name = "Clip-004",
                .bounds_s = continuous [
                    4.166666666666667,
                    4.416666666666667,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/credits.mov",
                    },
                    .bounds_s = continuous [
                        4.166666666666667,
                        4.416666666666667,
                    ],
                    .domain = picture {},
                },
                .metadata_hash = "d958f8c34514084d",
                .markers = [
                ],
            },
        ],
        .markers = [
        ],
    },
],
.presentation_space_discrete_partitions = {},
.metadata_map = {
    "b76b494dd822594b": {
        "clip_info": {
            "scene": "001",
            "take": "1",
            "camera": "A",
        },
        "colorist_notes": "Apply warm grade",
    },
    "04a1ce6df4c0f425": {
        "clip_info": {
            "scene": "002",
            "take": "3",
            "camera": "B",
        },
        "colorist_notes": "Match to previous shot",
    },
    "13fc06cbbe3e2a3e": {
        "clip_info": {
            "scene": "003",
            "take": "2",
            "camera": "A",
        },
        "colorist_notes": "Boost shadows",
    },
    "d958f8c34514084d": {
        "clip_info": {
            "scene": "credits",
            "take": "1",
            "camera": "static",
        },
        "colorist_notes": "Use standard credits grade",
    },
},
.markers = [
],

.schema_version = 1,
.name = "Mixed Video and Audio Tracks",
.children = [
    track {
        .name = "Video Track 1",
        .children = [
            clip {
                .name = "video_clip_1.mp4",
                .bounds_s = discrete [
                    0,
                    120,
                ],
                .media = {
                    .data_reference = null {},
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
        .name = "Video Track 2",
        .children = [
            clip {
                .name = "video_clip_2.mp4",
                .bounds_s = discrete [
                    0,
                    120,
                ],
                .media = {
                    .data_reference = null {},
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
        .name = "Video Track 3",
        .children = [
            clip {
                .name = "video_clip_3.mp4",
                .bounds_s = discrete [
                    0,
                    120,
                ],
                .media = {
                    .data_reference = null {},
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
        .name = "Video Track 4",
        .children = [
            clip {
                .name = "video_clip_4.mp4",
                .bounds_s = discrete [
                    0,
                    120,
                ],
                .media = {
                    .data_reference = null {},
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
        .name = "Audio Track 1",
        .children = [
            clip {
                .name = "audio_clip_1.wav",
                .bounds_s = discrete [
                    0,
                    240000,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = audio {},
                    .discrete_partition = {
                        .sample_rate_hz = Int 48000,
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
        .name = "Audio Track 2",
        .children = [
            clip {
                .name = "audio_clip_2.wav",
                .bounds_s = discrete [
                    0,
                    240000,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = audio {},
                    .discrete_partition = {
                        .sample_rate_hz = Int 48000,
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
        .name = "Audio Track 3",
        .children = [
            clip {
                .name = "audio_clip_3.wav",
                .bounds_s = discrete [
                    0,
                    240000,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = audio {},
                    .discrete_partition = {
                        .sample_rate_hz = Int 48000,
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
        .name = "Audio Track 4",
        .children = [
            clip {
                .name = "audio_clip_4.wav",
                .bounds_s = discrete [
                    0,
                    240000,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = audio {},
                    .discrete_partition = {
                        .sample_rate_hz = Int 48000,
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

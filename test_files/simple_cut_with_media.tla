.schema_version = 1,
.name = "Simple Cut with Media Reference",
.children = [
    track {
        .name = "Video Track",
        .children = [
            clip {
                .name = "App Screenshot",
                .bounds_s = continuous [
                    0.0,
                    5.0,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "../app.png",
                    },
                    .bounds_s = continuous [
                        0.0,
                        5.0,
                    ],
                    .domain = picture {},
                },
                .markers = [
                ],
            },
            clip {
                .name = "Second Clip",
                .bounds_s = continuous [
                    5.0,
                    10.0,
                ],
                .media = {
                    .data_reference = uri {
                        .target_uri = "file:///folder/other_clip.mov",
                    },
                    .bounds_s = continuous [
                        0.0,
                        5.0,
                    ],
                    .domain = picture {},
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

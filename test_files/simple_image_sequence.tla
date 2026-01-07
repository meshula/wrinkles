.schema_version = 1,
.name = "simple_image_sequence",
.children = [
    track {
        .name = "Video Track",
        .children = [
            clip {
                .name = "Image Sequence Clip",
                .bounds_s = discrete [
                    0,
                    48,
                ],
                .media = {
                    .data_reference = image_sequence {
                        .target_url_base = "/renders/shot_010/",
                        .name_prefix = "frame_",
                        .name_suffix = ".exr",
                        .start_frame = 1001,
                        .frame_step = 1,
                        .frame_zero_padding = 4,
                        .rate = 24.0,
                        .missing_frame_policy = "hold",
                    },
                    .bounds_s = discrete [
                        1001,
                        1101,
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

.schema_version = 1,
.name = "Clip-001-With-Metadata",
.children = [
    .track(.{
        .name = "Track-001",
        .children = [
            .clip(.{
                .name = "Clip-001-With-Metadata",
                .bounds_s = .discrete([
                    0,
                    3,
                ]),
                .media = .{
                    .data_reference = .uri(.{
                        .target_uri = "file:///folder/titles.mov",
                    }),
                    .bounds_s = .discrete([
                        0,
                        8,
                    ]),
                    .domain = .picture,
                    .discrete_partition = .{
                        .sample_rate_hz = .Integer(24),
                        .start_index = 0,
                    },
                },
                .metadata_hash = "4eda2567c141183c",
                .markers = [
                ],
            }),
        ],
        .markers = [
        ],
    }),
],
.presentation_space_discrete_partitions = .{},
.metadata_map = {
    "4eda2567c141183c": {
        "production": {
            "studio": "Test Studio",
            "project_code": "TST001",
        },
        "editorial": {
            "editor": "Jane Doe",
            "version": 3,
            "approved": true,
        },
        "tags": ["hero", "opening", "intro"],
    },
},
.markers = [
],

.schema_version = 1,
.name = "sc01_sh010_layerA",
.children = [
    track {
        .name = "",
        .children = [
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    17.866666666666667,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "sc01_sh010_anim.mov",
                .bounds_s = discrete [
                    0,
                    50,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 15,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "0479a26907f53d90",
                .markers = [
                ],
            },
        ],
        .markers = [
        ],
    },
    track {
        .name = "",
        .children = [
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    0.43333333333333335,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "sc01_sh010_anim.mov",
                .bounds_s = discrete [
                    0,
                    100,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "608a2c58e080db71",
                .markers = [
                ],
            },
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    1.7333333333333334,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "sc01_sh020_anim.mov",
                .bounds_s = discrete [
                    0,
                    157,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "8b60e805d8c31407",
                .markers = [
                ],
            },
            clip {
                .name = "sc01_sh030_anim.mov",
                .bounds_s = discrete [
                    0,
                    235,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "47f1fbb104e3a9ac",
                .markers = [
                    {
                        .name = "",
                        .marked_range = [
                            2.433333333333333,
                            2.433333333333333,
                        ],
                        .color = "red",
                        .comment = "",
                    },
                ],
            },
            transition {
                .name = "Cross Dissolve",
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
                .name = "",
                .bounds_s = [
                    0.0,
                    2.6333333333333333,
                ],
                .markers = [
                ],
            },
            stack {
                .name = "sc01_sh010_anim",
                .children = [
                ],
                .markers = [
                ],
            },
        ],
        .markers = [
        ],
    },
    track {
        .name = "",
        .children = [
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    0.5,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "test_title",
                .bounds_s = discrete [
                    108000,
                    108941,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "e7790436a85d2786",
                .markers = [
                ],
            },
        ],
        .markers = [
        ],
    },
    track {
        .name = "",
        .children = [
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    31.866666666666667,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "sc01_master_layerA_sh030_temp.mov",
                .bounds_s = discrete [
                    133,
                    341,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "97f533c2d177051b",
                .markers = [
                ],
            },
            transition {
                .name = "Cross Dissolve",
                .container = {
                    .name = "",
                    .children = [
                    ],
                    .markers = [
                    ],
                },
                .kind = "SMPTE_Dissolve",
            },
            clip {
                .name = "sc01_sh010_anim.mov",
                .bounds_s = discrete [
                    18,
                    100,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "71e9d8822537e397",
                .markers = [
                ],
            },
        ],
        .markers = [
        ],
    },
    track {
        .name = "",
        .children = [
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    0.43333333333333335,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "sc01_sh010_anim.mov",
                .bounds_s = discrete [
                    0,
                    100,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "425eb017951b32dc",
                .markers = [
                ],
            },
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    14.1,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "sc01_sh010_anim.mov",
                .bounds_s = discrete [
                    0,
                    100,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "819eb4e81109dead",
                .markers = [
                ],
            },
        ],
        .markers = [
        ],
    },
    track {
        .name = "",
        .children = [
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    11.166666666666666,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "sc01_placeholder.wav",
                .bounds_s = discrete [
                    8497,
                    8667,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "1541a35ffe7f083d",
                .markers = [
                ],
            },
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    4.366666666666666,
                ],
                .markers = [
                ],
            },
            stack {
                .name = "sc01_sh010_anim",
                .children = [
                ],
                .markers = [
                ],
            },
        ],
        .markers = [
        ],
    },
    track {
        .name = "",
        .children = [
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    5.1,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "track_08.wav",
                .bounds_s = discrete [
                    6896,
                    7094,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "60cd32df17802097",
                .markers = [
                ],
            },
        ],
        .markers = [
        ],
    },
    track {
        .name = "",
        .children = [
            gap {
                .name = "",
                .bounds_s = [
                    0.0,
                    31.866666666666667,
                ],
                .markers = [
                ],
            },
            clip {
                .name = "sc01_master_layerA_sh030_temp.mov",
                .bounds_s = discrete [
                    133,
                    354,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "8fe06f51a61e54cc",
                .markers = [
                ],
            },
            clip {
                .name = "sc01_sh010_anim.mov",
                .bounds_s = discrete [
                    6,
                    100,
                ],
                .media = {
                    .data_reference = null {},
                    .domain = picture {},
                    .discrete_partition = {
                        .sample_rate_hz = Integer 30,
                        .start_index = 0,
                    },
                },
                .metadata_hash = "c6bac7797491f8d0",
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
    "0479a26907f53d90": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-1",
            "alphatype": "none",
            "anamorphic": "FALSE",
            "enabled": "TRUE",
            "labels": {
                "label2": "Iris",
            },
            "link": [{
                "clipindex": "1",
                "linkclipref": "clipitem-1",
                "mediatype": "video",
                "trackindex": "1",
            }, {
                "clipindex": "2",
                "groupindex": "1",
                "linkclipref": "clipitem-14",
                "mediatype": "audio",
                "trackindex": "1",
            }, {
                "clipindex": "2",
                "groupindex": "1",
                "linkclipref": "clipitem-16",
                "mediatype": "audio",
                "trackindex": "2",
            }],
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-1",
            "pixelaspectratio": "square",
            "pproTicksIn": "0",
            "pproTicksOut": "846720000000",
        },
        "my_hook_function_was_here": true,
    },
    "608a2c58e080db71": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-2",
            "alphatype": "none",
            "enabled": "TRUE",
            "labels": {
                "label2": "Iris",
            },
            "link": [{
                "clipindex": "1",
                "linkclipref": "clipitem-2",
                "mediatype": "video",
                "trackindex": "2",
            }, {
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-13",
                "mediatype": "audio",
                "trackindex": "1",
            }, {
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-15",
                "mediatype": "audio",
                "trackindex": "2",
            }],
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-1",
            "pproTicksIn": "0",
            "pproTicksOut": "846720000000",
        },
        "my_hook_function_was_here": true,
    },
    "8b60e805d8c31407": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-3",
            "alphatype": "none",
            "anamorphic": "FALSE",
            "enabled": "TRUE",
            "labels": {
                "label2": "Iris",
            },
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-2",
            "pixelaspectratio": "square",
            "pproTicksIn": "0",
            "pproTicksOut": "1329350400000",
        },
        "my_hook_function_was_here": true,
    },
    "47f1fbb104e3a9ac": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-4",
            "alphatype": "none",
            "anamorphic": "FALSE",
            "enabled": "TRUE",
            "labels": {
                "label2": "Iris",
            },
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-3",
            "pixelaspectratio": "square",
            "pproTicksIn": "0",
            "pproTicksOut": "1989792000000",
        },
        "my_hook_function_was_here": true,
    },
    "e7790436a85d2786": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-10",
            "alphatype": "straight",
            "anamorphic": "FALSE",
            "enabled": "TRUE",
            "labels": {
                "label2": "Lavender",
            },
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-5",
            "pixelaspectratio": "square",
            "pproTicksIn": "914457600000000",
            "pproTicksOut": "922425235200000",
        },
        "my_hook_function_was_here": true,
    },
    "97f533c2d177051b": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-11",
            "alphatype": "none",
            "anamorphic": "FALSE",
            "enabled": "TRUE",
            "labels": {
                "label2": "Iris",
            },
            "link": [{
                "clipindex": "1",
                "linkclipref": "clipitem-11",
                "mediatype": "video",
                "trackindex": "4",
            }, {
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-23",
                "mediatype": "audio",
                "trackindex": "7",
            }, {
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-25",
                "mediatype": "audio",
                "trackindex": "8",
            }],
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-6",
            "pixelaspectratio": "square",
            "pproTicksIn": "287884800000",
            "pproTicksOut": "2159136000000",
        },
        "my_hook_function_was_here": true,
    },
    "71e9d8822537e397": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-12",
            "alphatype": "none",
            "enabled": "TRUE",
            "labels": {
                "label2": "Iris",
            },
            "link": [{
                "clipindex": "3",
                "linkclipref": "clipitem-12",
                "mediatype": "video",
                "trackindex": "4",
            }, {
                "clipindex": "2",
                "groupindex": "1",
                "linkclipref": "clipitem-24",
                "mediatype": "audio",
                "trackindex": "7",
            }, {
                "clipindex": "2",
                "groupindex": "1",
                "linkclipref": "clipitem-26",
                "mediatype": "audio",
                "trackindex": "8",
            }],
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-1",
            "pproTicksIn": "50803200000",
            "pproTicksOut": "846720000000",
        },
        "my_hook_function_was_here": true,
    },
    "425eb017951b32dc": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-13",
            "@premiereChannelType": "stereo",
            "enabled": "TRUE",
            "labels": {
                "label2": "Iris",
            },
            "link": [{
                "clipindex": "1",
                "linkclipref": "clipitem-2",
                "mediatype": "video",
                "trackindex": "2",
            }, {
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-13",
                "mediatype": "audio",
                "trackindex": "1",
            }, {
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-15",
                "mediatype": "audio",
                "trackindex": "2",
            }],
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-1",
            "pproTicksIn": "0",
            "pproTicksOut": "846720000000",
            "sourcetrack": {
                "mediatype": "audio",
                "trackindex": "1",
            },
        },
        "my_hook_function_was_here": true,
    },
    "819eb4e81109dead": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-14",
            "@premiereChannelType": "stereo",
            "enabled": "TRUE",
            "labels": {
                "label2": "Iris",
            },
            "link": [{
                "clipindex": "1",
                "linkclipref": "clipitem-1",
                "mediatype": "video",
                "trackindex": "1",
            }, {
                "clipindex": "2",
                "groupindex": "1",
                "linkclipref": "clipitem-14",
                "mediatype": "audio",
                "trackindex": "1",
            }, {
                "clipindex": "2",
                "groupindex": "1",
                "linkclipref": "clipitem-16",
                "mediatype": "audio",
                "trackindex": "2",
            }],
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-1",
            "pproTicksIn": "0",
            "pproTicksOut": "846720000000",
            "sourcetrack": {
                "mediatype": "audio",
                "trackindex": "1",
            },
        },
        "my_hook_function_was_here": true,
    },
    "1541a35ffe7f083d": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-17",
            "@premiereChannelType": "stereo",
            "enabled": "TRUE",
            "labels": {
                "label2": "Caribbean",
            },
            "link": [{
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-17",
                "mediatype": "audio",
                "trackindex": "3",
            }, {
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-19",
                "mediatype": "audio",
                "trackindex": "4",
            }],
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-7",
            "pproTicksIn": "0",
            "pproTicksOut": "1439424000000",
            "sourcetrack": {
                "mediatype": "audio",
                "trackindex": "1",
            },
        },
        "my_hook_function_was_here": true,
    },
    "60cd32df17802097": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-21",
            "@premiereChannelType": "stereo",
            "enabled": "TRUE",
            "labels": {
                "label2": "Caribbean",
            },
            "link": [{
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-21",
                "mediatype": "audio",
                "trackindex": "5",
            }, {
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-22",
                "mediatype": "audio",
                "trackindex": "6",
            }],
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-8",
            "pproTicksIn": "0",
            "pproTicksOut": "1676505600000",
            "sourcetrack": {
                "mediatype": "audio",
                "trackindex": "1",
            },
        },
        "my_hook_function_was_here": true,
    },
    "8fe06f51a61e54cc": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-23",
            "@premiereChannelType": "stereo",
            "enabled": "TRUE",
            "labels": {
                "label2": "Iris",
            },
            "link": [{
                "clipindex": "1",
                "linkclipref": "clipitem-11",
                "mediatype": "video",
                "trackindex": "4",
            }, {
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-23",
                "mediatype": "audio",
                "trackindex": "7",
            }, {
                "clipindex": "1",
                "groupindex": "1",
                "linkclipref": "clipitem-25",
                "mediatype": "audio",
                "trackindex": "8",
            }],
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-6",
            "pproTicksIn": "287884800000",
            "pproTicksOut": "2049062400000",
            "sourcetrack": {
                "mediatype": "audio",
                "trackindex": "1",
            },
        },
        "my_hook_function_was_here": true,
    },
    "c6bac7797491f8d0": {
        "fcp_xml": {
            "@frameBlend": "FALSE",
            "@id": "clipitem-24",
            "@premiereChannelType": "stereo",
            "enabled": "TRUE",
            "labels": {
                "label2": "Iris",
            },
            "link": [{
                "clipindex": "3",
                "linkclipref": "clipitem-12",
                "mediatype": "video",
                "trackindex": "4",
            }, {
                "clipindex": "2",
                "groupindex": "1",
                "linkclipref": "clipitem-24",
                "mediatype": "audio",
                "trackindex": "7",
            }, {
                "clipindex": "2",
                "groupindex": "1",
                "linkclipref": "clipitem-26",
                "mediatype": "audio",
                "trackindex": "8",
            }],
            "logginginfo": {
                "description": null,
                "lognote": null,
                "scene": null,
                "shottake": null,
            },
            "masterclipid": "masterclip-1",
            "pproTicksIn": "152409600000",
            "pproTicksOut": "846720000000",
            "sourcetrack": {
                "mediatype": "audio",
                "trackindex": "1",
            },
        },
        "my_hook_function_was_here": true,
    },
},
.markers = [
],

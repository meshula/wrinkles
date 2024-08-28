// header for exposing OTIO functions to c

typedef enum otio_ComposableTypes_t { timeline, stack, track, clip, gap, warp, err } otio_ComposableTypes_t;

typedef struct otio_ComposedValueRef {
    otio_ComposableTypes_t kind;
    void* ref;
} otio_ComposedValueRef;

typedef struct otio_TopologicalMap {
    void* ref;
} otio_TopologicalMap;

typedef struct otio_ProjectionOperatorMap {
    void* ref;
} otio_ProjectionOperatorMap;

otio_ComposedValueRef otio_read_from_file(char* filepath);
otio_ComposedValueRef otio_fetch_child_cvr_ind(
        otio_ComposedValueRef parent,
        int index
);
int otio_child_count_cvr(otio_ComposedValueRef parent);
otio_TopologicalMap otio_build_topo_map_cvr(otio_ComposedValueRef root);
otio_ProjectionOperatorMap otio_build_projection_op_map_to_media_tp_cvr(
    otio_TopologicalMap in_map,
    otio_ComposedValueRef root
);

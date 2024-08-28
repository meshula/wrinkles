// header for exposing OTIO functions to c

typedef enum otio_ComposableTypes_t { 
    otio_ct_timeline, 
    otio_ct_stack,
    otio_ct_track,
    otio_ct_clip,
    otio_ct_gap,
    otio_ct_warp,
    otio_ct_err 
} otio_ComposableTypes_t;

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

otio_ComposedValueRef otio_read_from_file(const char* filepath);
otio_ComposedValueRef otio_fetch_child_cvr_ind(
        otio_ComposedValueRef parent,
        int index
);
int otio_child_count_cvr(otio_ComposedValueRef parent);
otio_TopologicalMap otio_build_topo_map_cvr(otio_ComposedValueRef root);
void otio_write_map_to_png(otio_TopologicalMap, const char*);
otio_ProjectionOperatorMap otio_build_projection_op_map_to_media_tp_cvr(
    otio_TopologicalMap in_map,
    otio_ComposedValueRef root
);

#include <stdlib.h>
int otio_fetch_cvr_type_str(
        otio_ComposedValueRef self,
        char* result,
        size_t len
);
int otio_fetch_cvr_name_str(
        otio_ComposedValueRef self,
        char* result,
        size_t len
);

size_t otio_po_map_fetch_num_endpoints(otio_ProjectionOperatorMap in_map);
const float* otio_po_map_fetch_endpoints(otio_ProjectionOperatorMap in_map);

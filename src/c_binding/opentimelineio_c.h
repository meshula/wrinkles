// header for exposing OTIO functions to c

// Allocators
///////////////////////////////////////////////////////////////////////////////
typedef struct otio_Allocator {
    void* ref;
} otio_Allocator;
otio_Allocator otio_fetch_allocator_gpa();
typedef struct otio_Arena {
    void* arena;
    otio_Allocator allocator;
} otio_Arena;
otio_Arena otio_fetch_allocator_new_arena();
void otio_arena_deinit(otio_Arena);

// OpenTime
///////////////////////////////////////////////////////////////////////////////
typedef struct otio_ContinuousTimeRange {
    float start_seconds;
    float end_seconds;
} otio_ContinuousTimeRange;

// Hierarchy
///////////////////////////////////////////////////////////////////////////////
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


otio_ComposedValueRef otio_read_from_file(
        otio_Allocator,
        const char* filepath
 );
void otio_timeline_deinit(otio_ComposedValueRef root);

otio_ComposedValueRef otio_fetch_child_cvr_ind(
        otio_ComposedValueRef parent,
        int index
);
int otio_child_count_cvr(otio_ComposedValueRef parent);
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


// TopologicalMap
///////////////////////////////////////////////////////////////////////////////
typedef struct otio_TopologicalMap {
    void* ref;
} otio_TopologicalMap;

otio_TopologicalMap otio_build_topo_map_cvr(
        otio_Allocator allocator,
        otio_ComposedValueRef root
);
void otio_write_map_to_png(
        otio_Allocator allocator,
        otio_TopologicalMap,
        const char*
);

// Topologies
///////////////////////////////////////////////////////////////////////////////
typedef struct otio_Topology {
    void* ref;
} otio_Topology;

otio_Topology otio_fetch_topology(
        otio_Allocator allocator,
        otio_ComposedValueRef ref
);
int otio_topo_fetch_input_bounds(otio_Topology, const otio_ContinuousTimeRange*);
int otio_topo_fetch_output_bounds(otio_Topology, const otio_ContinuousTimeRange*);


// ProjectionOperatorMap
///////////////////////////////////////////////////////////////////////////////
typedef struct otio_ProjectionOperatorMap {
    void* ref;
} otio_ProjectionOperatorMap;

otio_ProjectionOperatorMap otio_build_projection_op_map_to_media_tp_cvr(
    otio_Allocator allocator,
    otio_TopologicalMap in_map,
    otio_ComposedValueRef root
);
size_t otio_po_map_fetch_num_endpoints(otio_ProjectionOperatorMap in_map);
const float* otio_po_map_fetch_endpoints(otio_ProjectionOperatorMap in_map);

size_t otio_po_map_fetch_num_operators_for_segment(
        otio_ProjectionOperatorMap in_map,
        size_t ind
);
typedef struct otio_ProjectionOperator {
    void* ref;
} otio_ProjectionOperator;
int otio_po_map_fetch_op(
        otio_ProjectionOperatorMap,
        size_t segment,
        size_t po_index,
        otio_ProjectionOperator* result
);
int otio_po_fetch_topology(otio_ProjectionOperator, otio_Topology*);
otio_ComposedValueRef otio_po_fetch_source(otio_ProjectionOperator);
otio_ComposedValueRef otio_po_fetch_destination(otio_ProjectionOperator);

// Spaces
///////////////////////////////////////////////////////////////////////////////
typedef enum otio_SpaceLabel { 
    otio_sl_presentation,
    otio_sl_media,
} otio_SpaceLabel;
typedef struct otio_DiscreteDatasourceIndexGenerator {
    uint32_t sample_rate_hz;
    size_t start_index;
} otio_DiscreteDatasourceIndexGenerator;

int otio_fetch_discrete_info(
        otio_ComposedValueRef,
        otio_SpaceLabel,
        otio_DiscreteDatasourceIndexGenerator*);
size_t otio_fetch_continuous_ordinate_to_discrete_index(
        otio_ComposedValueRef,
        float,
        otio_SpaceLabel);

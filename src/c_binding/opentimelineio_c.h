// header for exposing OTIO functions to c

#include <stdlib.h>

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
typedef struct otio_ContinuousInterval {
    float start;
    float end;
} otio_ContinuousInterval;

// Hierarchy
///////////////////////////////////////////////////////////////////////////////
typedef enum otio_ComposableTypes_t { 
    otio_ct_timeline, 
    otio_ct_stack,
    otio_ct_track,
    otio_ct_clip,
    otio_ct_gap,
    otio_ct_warp,
    otio_ct_transition,
    otio_ct_err 
} otio_ComposableTypes_t;

typedef struct otio_CompositionItemHandle {
    otio_ComposableTypes_t kind;
    void* ref;
} otio_CompositionItemHandle;


otio_CompositionItemHandle otio_read_from_file(
        otio_Allocator,
        const char* filepath
 );
void otio_timeline_deinit(otio_CompositionItemHandle root);

otio_CompositionItemHandle otio_fetch_child_cvr_ind(
        otio_CompositionItemHandle parent,
        int index
);
int otio_child_count_cvr(otio_CompositionItemHandle parent);
int otio_fetch_cvr_type_str(
        otio_CompositionItemHandle self,
        char* result,
        size_t len
);
int otio_fetch_cvr_name_str(
        otio_CompositionItemHandle self,
        char* result,
        size_t len
);

// Topologies
///////////////////////////////////////////////////////////////////////////////
typedef struct otio_Topology {
    void* ref;
} otio_Topology;

otio_Topology otio_fetch_topology(
        otio_Allocator allocator,
        otio_CompositionItemHandle ref
);
int otio_topo_fetch_input_bounds(otio_Topology, const otio_ContinuousInterval*);
int otio_topo_fetch_output_bounds(otio_Topology, const otio_ContinuousInterval*);


// ProjectionTopology
///////////////////////////////////////////////////////////////////////////////
typedef struct otio_ProjectionTopology {
    void* ref;
} otio_ProjectionTopology;

otio_ProjectionTopology otio_build_projection_op_map_to_media_tp_cvr(
    otio_Allocator allocator,
    otio_CompositionItemHandle root
);
size_t otio_po_map_fetch_num_endpoints(otio_ProjectionTopology in_map);
const float* otio_po_map_fetch_endpoints(otio_ProjectionTopology in_map);

size_t otio_po_map_fetch_num_operators_for_segment(
        otio_ProjectionTopology in_map,
        size_t ind
);
typedef struct otio_ProjectionOperator {
    void* ref;
} otio_ProjectionOperator;
int otio_po_map_fetch_op(
        otio_ProjectionTopology,
        size_t segment,
        size_t po_index,
        otio_ProjectionOperator* result
);
int otio_po_fetch_topology(otio_ProjectionOperator, otio_Topology*);
otio_CompositionItemHandle otio_po_fetch_source(otio_ProjectionOperator);
otio_CompositionItemHandle otio_po_fetch_destination(otio_ProjectionOperator);

void otio_write_map_to_png(
        otio_Allocator allocator,
        otio_ProjectionTopology projection_builder,
        const char*
);

// Domains
///////////////////////////////////////////////////////////////////////////////
typedef enum otio_Domain {
    otio_dm_time,
    otio_dm_picture,
    otio_dm_audio,
    otio_dm_metadata,
    otio_dm_other,
} otio_Domain;
///////////////////////////////////////////////////////////////////////////////

// Spaces
///////////////////////////////////////////////////////////////////////////////
typedef enum otio_SpaceLabel { 
    otio_sl_presentation,
    otio_sl_media,
} otio_SpaceLabel;
typedef struct otio_Rational {
    uint32_t num;
    uint32_t den;
} otio_Rational;
typedef struct otio_DiscreteDatasourceIndexGenerator {
    otio_Rational sample_rate_hz;
    size_t start_index;
} otio_DiscreteDatasourceIndexGenerator;

int otio_fetch_discrete_info(
        otio_CompositionItemHandle,
        otio_SpaceLabel,
        otio_Domain,
        otio_DiscreteDatasourceIndexGenerator*);
size_t otio_fetch_continuous_ordinate_to_discrete_index(
        otio_CompositionItemHandle,
        float,
        otio_SpaceLabel,
        otio_Domain);

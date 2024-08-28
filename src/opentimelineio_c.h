// header for exposing OTIO functions to c

int test_fn();

//                      0         1      2     3      4     5    6
enum ComposableTypes { timeline, stack, track, clip, gap, warp, err };
typedef enum ComposableTypes ComposableTypes_t;

struct ComposedValueRef_c {
    ComposableTypes_t kind;
    void* ref;
};

struct ComposedValueRef_c read_otio_timeline_from_file(char* filepath);
struct ComposedValueRef_c get_child_ref_by_index(struct ComposedValueRef_c, int);
int get_child_count(struct ComposedValueRef_c);
void* build_topological_map(struct ComposedValueRef_c);
void* build_projection_operator_map_media(void*, struct ComposedValueRef_c);

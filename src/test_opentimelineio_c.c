#include <stdio.h>
 
#include "opentimelineio_c.h"

int main()
{
    printf("\nTESTING C CALLING ZIG FUNCTIONS\n\n");
    int result = test_fn();

    printf("result: %d\n", result);

    struct ComposedValueRef_c tl = read_otio_timeline_from_file(
        "/Users/stephan/workspace/wrinkles/sample_otio_files/simple_cut.otio"
    );
    printf("read timeline: %p, children: %d\n", tl.ref, get_child_count(tl));

    struct ComposedValueRef_c tr = get_child_ref_by_index(tl, 0);
    printf("read track: %p, children: %d\n", tr.ref, get_child_count(tr));

    void* map = build_topological_map(tl);
    printf("built map: %p\n", map);

    struct ComposedValueRef_c cl = get_child_ref_by_index(tr, 0);
    printf("read clip: %p\n", cl.ref);

    printf("C CODE DONE\n\n");
}

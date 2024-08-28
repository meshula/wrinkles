#include <stdio.h>
#include <string.h>
 
#include "opentimelineio_c.h"

/* Prototype C wrapper around "wrinkles" codebase
 *
 * A C-interface needs to be able to, in order to be considered "complete",
 * - Read and Write .otio files
 * - Traverse the Hierarchy
 * - construct a timeline from scratch
 * - Quary/set fields on objects (name, ranges, etc)
 * - build projection operators, maps, and a projection_operator_map
 */

int main()
{
    char buf[1024];

    printf("\nTESTING C CALLING ZIG FUNCTIONS\n\n");

    otio_ComposedValueRef tl = otio_read_from_file(
        "/Users/stephan/workspace/wrinkles/sample_otio_files/simple_cut.otio"
    );
    otio_fetch_cvr_type_str(tl, buf, 1024);
    printf(
            "read timeline: %p, children: %d type: %s\n",
            tl.ref,
            otio_child_count_cvr(tl),
            buf
    );

    otio_ComposedValueRef tr = otio_fetch_child_cvr_ind(tl, 0);
    otio_fetch_cvr_type_str(tr, buf, 1024);
    printf(
        "read track: %p, children: %d, type: %s\n",
        tr.ref,
        otio_child_count_cvr(tr),
        buf
    );

    // why does this cause an index out of bounds panic?
    otio_ComposedValueRef ch = otio_fetch_child_cvr_ind(tr, 0);
    otio_fetch_cvr_type_str(ch, buf, 1024);
    printf("read child: %p, type: %s\n", ch.ref, buf);

    otio_TopologicalMap map = otio_build_topo_map_cvr(tr);
    printf("built map: %p\n", map.ref);

    otio_write_map_to_png(map, "/var/tmp/from_c_map.dot");

    // causes a "not implemented error"
    otio_ProjectionOperatorMap po = otio_build_projection_op_map_to_media_tp_cvr(map, tl);
    printf("built po map to media: %p\n", po.ref);

    otio_ComposedValueRef cl = otio_fetch_child_cvr_ind(tr, 0);
    printf("read clip: %p\n", cl.ref);

    printf("C CODE DONE\n\n");
}

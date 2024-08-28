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

    // read the file
    ///////////////////////////////////////////////////////////////////////////

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

    // traverse children
    ///////////////////////////////////////////////////////////////////////////

    otio_ComposedValueRef tr = otio_fetch_child_cvr_ind(tl, 0);
    otio_fetch_cvr_type_str(tr, buf, 1024);
    printf(
        "read track: %p, children: %d, type: %s\n",
        tr.ref,
        otio_child_count_cvr(tr),
        buf
    );

    const int nchildren = otio_child_count_cvr(tr);

    printf("children:\n");

    for (int i = 0; i < nchildren; i++)
    {
        otio_ComposedValueRef ch = otio_fetch_child_cvr_ind(tr, i);
        otio_fetch_cvr_type_str(ch, buf, 1024);
        printf(" [%d] read child: %p, type: %s\n", i, ch.ref, buf);
    }

    // build a topological map
    ///////////////////////////////////////////////////////////////////////////

    otio_TopologicalMap map = otio_build_topo_map_cvr(tl);
    printf("built map: %p\n", map.ref);

    otio_write_map_to_png(map, "/var/tmp/from_c_map.dot");

    // build a projection operator map to media
    ///////////////////////////////////////////////////////////////////////////

    // causes a "not implemented error"
    otio_ProjectionOperatorMap po = (
            otio_build_projection_op_map_to_media_tp_cvr(map, tl)
    );
    const size_t n_endpoints = otio_po_map_fetch_num_endpoints(po);
    printf(
            "built po map to media: %p with %ld endpoints.\n",
            po.ref,
            n_endpoints
    );

    const float* endpoints = otio_po_map_fetch_endpoints(po);

    for (int i=0; i < n_endpoints; i++) 
    {
        printf(" [%d]: %g\n", i, endpoints[i]);
    }

    printf("C CODE DONE\n\n");
}

#include <stdio.h>
#include <string.h>
 
#include "opentimelineio_c.h"

/* Prototype C wrapper around "wrinkles" codebase
 *
 * A C-interface needs to be able to, in order to be considered "complete",
 * - Read and Write .otio files
 * - handle updating schemas
 * - Traverse the Hierarchy
 * - construct a timeline from scratch
 * - Quary/set fields on objects (name, ranges, etc)
 * - build projection operators, maps, and a projection_operator_map
 */

// print the tree w/ printf from this node and down
void
print_tree(
        // the reference to start at
        otio_ComposedValueRef root_ref,
        int indent)
{
    const size_t nchildren = otio_child_count_cvr(root_ref);

    // info about root_ref
    {
        char name_buf[1024];
        otio_fetch_cvr_name_str(root_ref, name_buf, 1024);

        char type_buf[1024];
        otio_fetch_cvr_type_str(root_ref, type_buf, 1024);

        printf(
            "%*s%s '%s' ",
            indent,
            "",
            type_buf,
            name_buf
        );

        {
            const otio_Topology topo = otio_fetch_topology(root_ref);
            const otio_ContinuousTimeRange input_bounds;

             if (topo.ref != 0) {
                 otio_topo_fetch_input_bounds(topo, &input_bounds);
                 printf(" [%g, %g) ", input_bounds.start_seconds, input_bounds.end_seconds);
             }
        }

        if (nchildren > 0) 
        {
            printf("[children: %lu]", nchildren);
        }
        printf("\n");
    }

    if (root_ref.kind == otio_ct_err) {
        return;
    }

    // recurse into children
    for (int i=0; i<nchildren; i++)
    {
        print_tree(otio_fetch_child_cvr_ind(root_ref, i), indent + 2);
    }
}

int 
main()
{
    printf("\nTESTING C CALLING ZIG FUNCTIONS\n\n");

    // read the file
    ///////////////////////////////////////////////////////////////////////////
    otio_ComposedValueRef tl = otio_read_from_file(
        "/Users/stephan/workspace/yaml_usd/dino/good_dino.updated.otio"
        // "/Users/stephan/workspace/wrinkles/sample_otio_files/simple_cut.otio"
        // "/Users/stephan/workspace/wrinkles/sample_otio_files/multiple_track.otio"
    );

    // traverse children
    ///////////////////////////////////////////////////////////////////////////
    print_tree(tl, 0);

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

    // clean up datastructure
    ///////////////////////////////////////////////////////////////////////////
    otio_timeline_deinit(tl);
    printf("freed tl.\n");

    printf("C CODE DONE\n\n");
}

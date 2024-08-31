#include <stdio.h>
#include <string.h>
 
#include "opentimelineio_c.h"

#include <signal.h>


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
        otio_Arena arena,
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
            otio_Topology topo = otio_fetch_topology(arena.allocator, root_ref);
            otio_ContinuousTimeRange input_bounds;

            otio_DiscreteDatasourceIndexGenerator di;
            otio_SpaceLabel di_space = -1;
            if (!otio_fetch_discrete_info(root_ref, otio_sl_presentation, &di)) 
            {
                di_space = otio_sl_presentation;
            }
            if (!otio_fetch_discrete_info(root_ref, otio_sl_media, &di))
            {
                di_space = otio_sl_media;
            }

            if (topo.ref != 0) 
            {
                otio_topo_fetch_input_bounds(topo, &input_bounds);

                if (di_space != -1) 
                {
                    size_t discrete_start = otio_fetch_continuous_ordinate_to_discrete_index(
                        root_ref, 
                        input_bounds.start_seconds,
                        di_space
                    );
                    size_t discrete_end = otio_fetch_continuous_ordinate_to_discrete_index(
                        root_ref, 
                        input_bounds.end_seconds,
                        di_space
                    );

                    const char* d_space_name = (
                            di_space == otio_sl_media ? 
                            "media" 
                            : "presentation"
                    );

                    printf(
                            " [%lu, %lu) ",
                            discrete_start,
                            discrete_end
                    );

                } else {
                    printf(
                            " [%g, %g) ",
                            input_bounds.start_seconds,
                            input_bounds.end_seconds
                    );
                }
            }

            if (di_space == otio_sl_presentation) {
                printf(" | discrete presentation: %d hz ", di.sample_rate_hz );
            }
            if (di_space == otio_sl_media) {
                printf(" | discrete media: %d hz ", di.sample_rate_hz );
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
        print_tree(
                arena,
                otio_fetch_child_cvr_ind(root_ref, i),
                indent + 2
        );
    }
}

int 
main(
        int argc,
        char** argv
)
{
    printf("\nTESTING C CALLING ZIG FUNCTIONS\n\n");

    // build an arena
    ///////////////////////////////////////////////////////////////////////////
    otio_Arena arena = otio_fetch_allocator_new_arena();

     if (argc < 2) {
         printf("Error: required argument filepath.\n");
         return -1;
     }

     int make_map = 0;
     for (int i=0; i<argc; i++)
     {
         if (strncmp(argv[i], "-m", 2) == 0) {
             make_map = 1;
             break;
         }
     }

    // read the file
    ///////////////////////////////////////////////////////////////////////////
    otio_ComposedValueRef tl = otio_read_from_file(arena.allocator, argv[1]);

    if (tl.kind == otio_ct_err) {
        printf("error reading file.\n");
        return -1;
    }

    // traverse children
    ///////////////////////////////////////////////////////////////////////////
    print_tree(arena, tl, 0);

    printf("done.\n");

    if (make_map == 0) 
    {
        otio_arena_deinit(arena);

        printf("freed tl.\n");

        return 0;
    }

    // build a topological map
    ///////////////////////////////////////////////////////////////////////////

    otio_TopologicalMap map = otio_build_topo_map_cvr(arena.allocator, tl);
    printf("built map: %p\n", map.ref);

    // otio_write_map_to_png(arena.allocator, map, "/var/tmp/from_c_map.dot");

    // build a projection operator map to media
    ///////////////////////////////////////////////////////////////////////////

    // causes a "not implemented error"
    otio_ProjectionOperatorMap po_map = (
            otio_build_projection_op_map_to_media_tp_cvr(
                arena.allocator,
                map,
                tl
            )
    );
    const size_t n_endpoints = otio_po_map_fetch_num_endpoints(po_map);
    printf(
            "built po_map to media: %p with %ld endpoints.\n",
            po_map.ref,
            n_endpoints
    );

    const float* endpoints = otio_po_map_fetch_endpoints(po_map);

    for (int i=0; i < n_endpoints; i++) 
    {
        printf(" [%d]: %g\n", i, endpoints[i]);
    }

    printf("segments:\n");

    for (int i=0; i < n_endpoints-1; i++) 
    {

        const size_t ops = otio_po_map_fetch_num_operators_for_segment(po_map, i);

        printf(" [%d]: ops: %lu [%g, %g) ", i, ops, endpoints[i], endpoints[i+1]);

        for (int o=0; o<ops; o++)
        {
            otio_ProjectionOperator po;
            otio_Topology topo;
            otio_ContinuousTimeRange tr;

            if (!otio_po_map_fetch_op( po_map, i, o, &po)) {
                otio_ComposedValueRef dest = otio_po_fetch_destination(po);

                if (!otio_po_fetch_topology(po, &topo)) {
                    if (!otio_topo_fetch_output_bounds(topo, &tr)) {
                        otio_DiscreteDatasourceIndexGenerator di;
                        otio_SpaceLabel di_space = -1;
                        if (!otio_fetch_discrete_info(dest, otio_sl_media, &di))
                        {
                            di_space = otio_sl_media;
                            if (di_space != -1) 
                            {
                                size_t discrete_start = otio_fetch_continuous_ordinate_to_discrete_index(
                                        dest, 
                                        tr.start_seconds,
                                        di_space
                                );
                                size_t discrete_end = otio_fetch_continuous_ordinate_to_discrete_index(
                                        dest, 
                                        tr.end_seconds,
                                        di_space
                                );

                                printf(
                                        "\n                    -> [%lu, %lu) ",
                                        discrete_start,
                                        discrete_end
                                      );

                                if (di_space == otio_sl_media) {
                                    printf(" | discrete media: %d hz ", di.sample_rate_hz );
                                }
                            } else {
                                printf(
                                        "-> [%g, %g) ",
                                        tr.start_seconds,
                                        tr.end_seconds
                                      );
                            }
                        }
                    }
                }
            }
        }
        
        printf("\n");
    }

    // clean up datastructure
    ///////////////////////////////////////////////////////////////////////////
    otio_arena_deinit(arena);

    printf("freed tl.\n");

    printf("C CODE DONE\n\n");
}

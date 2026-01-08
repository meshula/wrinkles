"""
Wrinkles - Python bindings for the temporal hierarchy library.

This module provides access to OpenTimelineIO-compatible timeline structures
and temporal projection capabilities.

Example usage:

    import wrinkles

    # Read a timeline
    timeline = wrinkles.read_from_file("project.otio")

    # Access structure
    print(timeline.name)
    for track in timeline.tracks:
        print(f"Track: {track.name}")
        for item in track:
            print(f"  {type(item).__name__}: {item.name}")

    # Build projection operators
    projections = wrinkles.build_projection_map(timeline)
    for proj in projections:
        result = proj.project_cc(0.0)
        print(f"Projected: {result}")
"""

from ._wrinkles import (
    # Schema types
    Timeline,
    Stack,
    Track,
    Clip,
    Gap,
    Warp,
    Transition,
    # Value types
    ContinuousInterval,
    # Projection types
    ProjectionOperator,
    # Functions
    read_from_file,
    build_projection_map,
    # Domain constants
    DOMAIN_TIME,
    DOMAIN_PICTURE,
    DOMAIN_AUDIO,
    DOMAIN_METADATA,
)

__version__ = "0.1.0"

__all__ = [
    # Schema types
    "Timeline",
    "Stack",
    "Track",
    "Clip",
    "Gap",
    "Warp",
    "Transition",
    # Value types
    "ContinuousInterval",
    # Projection types
    "ProjectionOperator",
    # Functions
    "read_from_file",
    "build_projection_map",
    # Domain constants
    "DOMAIN_TIME",
    "DOMAIN_PICTURE",
    "DOMAIN_AUDIO",
    "DOMAIN_METADATA",
]

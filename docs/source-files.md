
# Source code overview

```mermaid

graph TB
    %% Layer 0: Foundations
    subgraph foundations["Layer 0: Foundations"]
        string_stuff["string_stuff<br/>(string utilities)"]
        build_options["build_options<br/>(compiler config)"]
        comath["comath<br/>(external: math)"]
        wav["wav<br/>(external: WAV I/O)"]
        kissfft["kissfft<br/>(C: FFT)"]
        libsamplerate["libsamplerate<br/>(C: resampling)"]
        spline_gym["spline_gym<br/>(C: hodographs)"]
    end

    %% Layer 1: Core Time Mathematics
    subgraph layer1["Layer 1: Core Time Mathematics"]
        treecode["treecode<br/>(graph paths)"]
        opentime["opentime<br/>(points, intervals,<br/>transforms, duals)"]
    end

    %% Layer 2: Curve Mathematics
    subgraph layer2["Layer 2: Curve Mathematics"]
        curve["curve<br/>(linear & bezier<br/>splines)"]
    end

    %% Layer 3: Continuous Projections
    subgraph layer3["Layer 3: Continuous Projections"]
        topology["topology<br/>(mapping sets,<br/>monotonic projection)"]
    end

    %% Layer 4: Discrete Operations
    subgraph layer4["Layer 4: Discrete Space Operations"]
        sampling["sampling<br/>(discrete/continuous<br/>boundary ops)"]
    end

    %% Layer 5: Editorial Integration
    subgraph layer5["Layer 5: Editorial Integration"]
        opentimelineio["opentimelineio<br/>(timeline structures,<br/>OTIO integration)"]
    end

    %% C Binding Layer
    subgraph cbinding["C Binding Layer"]
        opentimelineio_c["opentimelineio_c<br/>(C API wrapper)"]
    end

    %% Foundation dependencies
    treecode --> build_options
    opentime --> string_stuff
    opentime --> comath
    opentime --> build_options

    %% Curve dependencies
    curve --> spline_gym
    curve --> string_stuff
    curve --> opentime
    curve --> comath

    %% Topology dependencies
    topology --> opentime
    topology --> curve

    %% Sampling dependencies (complex)
    sampling --> libsamplerate
    sampling --> kissfft
    sampling --> curve
    sampling --> wav
    sampling --> opentime
    sampling --> topology
    sampling --> build_options

    %% OTIO dependencies (synthesizes everything)
    opentimelineio --> string_stuff
    opentimelineio --> opentime
    opentimelineio --> curve
    opentimelineio --> topology
    opentimelineio --> treecode
    opentimelineio --> sampling
    opentimelineio --> build_options

    %% C binding dependencies
    opentimelineio_c --> opentime
    opentimelineio_c --> opentimelineio
    opentimelineio_c --> topology

    %% Styling
    classDef foundationStyle fill:#e1f5ff,stroke:#0077be,stroke-width:2px,color:#000
    classDef layer1Style fill:#fff4e1,stroke:#ff8c00,stroke-width:2px,color:#000
    classDef layer2Style fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000
    classDef layer3Style fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px,color:#000
    classDef layer4Style fill:#ffe0b2,stroke:#e65100,stroke-width:2px,color:#000
    classDef layer5Style fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#000
    classDef cbindingStyle fill:#e0e0e0,stroke:#424242,stroke-width:2px,color:#000
    classDef externalStyle fill:#fce4ec,stroke:#880e4f,stroke-width:1px,stroke-dasharray: 5 5,color:#000

    class string_stuff,build_options foundationStyle
    class comath,wav,kissfft,libsamplerate,spline_gym externalStyle
    class treecode,opentime layer1Style
    class curve layer2Style
    class topology layer3Style
    class sampling layer4Style
    class opentimelineio layer5Style
    class opentimelineio_c cbindingStyle

```


## Root Structure (26 items)
**Core Build System:**
- `build.zig` (25KB) - Primary Zig build configuration
- `build.zig.zon` - Zig package dependencies
- `Makefile` - Legacy/alternative build system

**Source Code:**
- `src/` - **Main source directory** (explored below)
- `libs/` - External dependencies
- `c_binding/` - C API layer

**Documentation:**
- `README.md` (15.7KB) - Project documentation
- `PROJECTION_TERMS.md` - Terminology definitions
- `notes.md` - Development notes
- `docs/` - Additional documentation

**Data & Examples:**
- `sample_otio_files/` - OpenTimelineIO test data
- `segments/`, `curves/` - Example data
- `spline-gym/`, `wrinkles-book/` - Research/book materials

**Build Artifacts:**
- `zig-out/`, `.zig-cache/` - Build outputs
- `.staging/` - Inception MCP staging area

---

## Source Architecture (`src/` - 23 items)

### Core Library Modules (Directories)
**`opentime/`** - Low-level temporal mathematics
- Points, intervals, affine transforms
- Dual arithmetic for implicit differentiation

**`curve/`** - Spline mathematics
- Linear and bezier curve structures
- Curve manipulation functions

**`sampling/`** - Discrete space handling
- Sample/index set operations
- Transformation and resampling

**`topology/`** - Continuous projection framework
- Mapping sets for space transformation
- Monotonic projection operations

**`treecode/`** - Graph path encoding
- Path encoding through graphs
- Map structure for graph navigation

**`opentimelineio/`**
- Editorial document structures
- Timeline representation
- OTIO integration layer

### Primary Implementation Files
**Core Systems:**
- `wrinkles.zig` (16KB) - Main application orchestration
- `wrinkles_visual_debugger.zig` (24KB) - Visual debugging interface
- `transformation_visualizer.zig` (15KB) - Transformation visualization
- `sampling.zig` (64KB) - **Largest module** - discrete space operations
- `curvet.zig` (74KB) - **Largest module** - curve operations

**OTIO Integration:**
- `otio_measure_timeline.zig` - Timeline measurement
- `otio_dump_graph.zig` - Graph visualization output

**Graphics/UI:**
- `wrinkles_*.wgsl` (WGSL shaders) - WebGPU shader programs
- `blank_fs.wgsl` - Fragment shader
- `example_zgui_app.zig` - Dear ImGui example
- `sokol_test.zig` - Sokol graphics testing

**C Binding Layer:**
- `c_binding/` - C API wrapper for library functions

---

## Architectural Assessment

**Language**: Zig (primary) with C bindings and WGSL shaders

**Pattern**: Library-first design with layered dependencies matching the README diagram:
```
opentime → sampling/curve
    ↓           ↓
  treecode → topology → ProjectionOperator → OpenTimelineIO
```

**Scale**: ~190KB of core Zig code across ~23 files, with heavy concentration in curve and sampling modules.

**Purpose**: Research prototype exploring temporal mathematics at the continuous/discrete boundary for editorial timeline applications.


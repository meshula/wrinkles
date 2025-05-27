# Wrinkles in Time
## Stephan Steinbach & Nick Porcino
Pixar Animation Studios, 2025

## Preface

This work began with the realization that the authors found ourselves, yet again, implementing a set of time warping and frame snapping heuristics as we brought up yet another piece of software that relied on simple temporal operations across different media composition systems. Operations that should produce identical results between systems often didn't, creating unpredictable workflows for artists and engineers alike. We thought that if we could just spend a couple of weeks and create a simple library of functions for computations on time for digital media, and that if we shared that library we could perhaps help introduce consistency to the broader development landscape. After putting together a sketch for an initial library, it quickly became apparent than the problem was harder than we thought.

What we thought might take weeks became a years-long exploration. We discovered that while time is fundamental to media composition—where video clips at different frame rates must synchronize with audio at independent sampling rates—there was surprisingly little literature providing a comprehensive mathematical treatment of temporal operations. We decided to take a step back, and try to derive a mathematical framework from first principles.

We began by following Euclid's approach in Elements, starting with a point in time conceptualized as an infinite half-space dividing past from future, and derived a geometry of time. The rest of the framework followed, treating time as a normed vector space subject to mathematical operations, coordinate systems, and affine transformations to temporal topology and sampling theory, ultimately creating a unified model that represents the complete cycle of temporal transformations in media from capture to presentation. This book reflects that journey, providing both the theoretical foundations and practical applications of our time algebra in real-world systems like OpenTimelineIO.

The title of this work draws inspiration from concepts that span both literature and physics.

In Madeline L'Engle's classic novel "A Wrinkle in Time", the tesseract allows characters to "fold" space-time, creating a shortcut between distant points by projecting through a higher dimension. This is conceptualized as creating a wrinkle or fold that brings two distant temporal-spatial points together.

In this work, projection operations transform time across different domains, enabling different temporal experiences and manipulations by mapping from one coordinate system to another to satisfy a "certain point of view," just as the tesseract in L'Engle's universe allows connection between otherwise discontinuous points in space-time. The title "Wrinkles in Time" thus takes on a dual meaning—referring both to the technical transformations we apply to temporal domains and to the broader narrative framework of manipulating time's fabric that is central to art itself. Story telling breaks the continuity of time and space to create a narrative world.

In Feynman's interpretation of quantum electrodynamics, he proposed that positrons (the antimatter counterpart of electrons) could be mathematically described as electrons moving backward in time. In his space-time diagrams, a positron traveling from point A to point B in space-time is equivalent to an electron traveling backward in time from point B to point A.

This seemingly counterintuitive concept becomes elegantly simple when viewed through the lens of the temporal framework we introduce:

- **Relative Temporal Perspective**: The framework's temporal projections show that time can be viewed from different coordinate systems ~ Feynman's interpretation reveals that the "direction" of time depends on the observer's reference frame. What appears as backward motion in one coordinate system (the laboratory frame) is actually forward motion in another coordinate system (the particle's own frame).
- **Topological Transformation**: The framework's temporal topologies demonstrate that this as a projection between two temporal topologies - the "observer topology" and the "positron topology" - where the mapping function between them inverts the direction of time.
- **No Paradox Required**: Just as the framework handles discontinuous intervals and differing rates of time without creating paradoxes, Feynman's interpretation resolves apparent contradictions by recognizing that different entities can experience time differently.
- **Unified Mathematical Framework**: Feynman's diagrams and the temporal topologies developed here use mathematical transformations to reconcile seemingly contradictory temporal experiences into a consistent framework.

In media composition, we often need to represent processes that appear to flow backward (like rewind effects), yet these processes must actually be implemented as forward processes in the underlying system. This mirrors how Feynman's backward-in-time positron is actually a manifestation of ordinary quantum field theory without requiring new physics.

In essence, both the temporal topology developed in this book, and Feynman's interpretation demonstrate that apparent temporal paradoxes can be resolved by acknowledging that time's directionality and flow depend on the coordinate system and projection being applied. What appears as a "wrinkle" in time from one perspective is simply a different mapping of the same underlying reality.

This connection suggests that our framework might have applications beyond media composition - potentially offering insights into how to mathematically represent complex temporal phenomena in physics and other fields.

We are pleased to present 'Wrinkles in Time' as a guide to your own exploration of time in media composition, and hope that the framework presented here will bring consistency, precision, and new creative possibilities to the next generation of media creation tools.

# Table of Contents - Wrinkles in Time

## Preface
- [Genesis of the work](wrinkles-in-time.md#preface)
- [Authors' journey](wrinkles-in-time.md#preface)
- [Purpose and scope](wrinkles-in-time.md#preface)

## Introduction
- [Time in Media Composition Systems](wrinkles-in-time.md#time-in-media-composition-systems)
- [Historical Context](wrinkles-in-time.md#historical-context)
- [The Current Challenge](wrinkles-in-time.md#the-current-challenge)
- [A New Approach](wrinkles-in-time.md#a-new-approach)

## Chapter 1: Media Composition Time Challenges
- [The Problem of Multiple Temporal Rates](wrinkles-in-time.md#the-problem-of-multiple-temporal-rates)
- [Today's Conform-Based Workflow](wrinkles-in-time.md#todays-conform-based-workflow)
- [Problems with the Conform-Based Approach](wrinkles-in-time.md#problems-with-the-conform-based-approach)
- [Tomorrow's Natural-Rate Based Workflow](wrinkles-in-time.md#tomorrows-natural-rate-based-workflow)
- [Benefits of the Natural-Rate Approach](wrinkles-in-time.md#benefits-of-the-natural-rate-approach)

## Chapter 2: Domains of Time
- [The Wheel of Creation](wrinkles-in-time.md#the-wheel-of-creation)
- [The Production Loop](wrinkles-in-time.md#the-production-loop)
  - [Narrative Time](wrinkles-in-time.md#narrative-time)
  - [Capture Time](wrinkles-in-time.md#capture-time)
  - [Media Time](wrinkles-in-time.md#media-time)
  - [Composition Time](wrinkles-in-time.md#composition-time)
  - [Presentation Time](wrinkles-in-time.md#presentation-time)
  - [Observation Time](wrinkles-in-time.md#observation-time)
  - [Participation Time](wrinkles-in-time.md#participation-time)
  - [Generation Time](wrinkles-in-time.md#generation-time)
  - [Reification Time](wrinkles-in-time.md#reification-time)
  - [Rendering Time](wrinkles-in-time.md#rendering-time)
- [The Real-Time Loop](wrinkles-in-time.md#the-real-time-loop)
- [Relationships Between Domains](wrinkles-in-time.md#relationships-between-domains)

## Chapter 3: Mathematical Foundations of Time
- [From First Principles](wrinkles-in-time.md#from-first-principles)
- [Define a Metric Space](wrinkles-in-time.md#define-a-metric-space)
- [Time as an Ordinate and Separating Plane](wrinkles-in-time.md#time-as-an-ordinate-and-separating-plane)
- [Intervals](wrinkles-in-time.md#intervals)
- [Coordinate Systems & Topology](wrinkles-in-time.md#coordinate-systems--topology)
  - [Interval Algebra](wrinkles-in-time.md#interval-algebra)
  - [Affine Transformations](wrinkles-in-time.md#affine-transformations)
  - [Change of Basis Transformation](wrinkles-in-time.md#change-of-basis-transformation)
- [Normed Vector Spaces & Intervals](wrinkles-in-time.md#normed-vector-spaces--intervals)
- [Time Algebra Elements and Operations](wrinkles-in-time.md#time-algebra-elements-and-operations)

## Chapter 4: Temporal Topology
- [A Tree, In Not So Many Bits](wrinkles-in-time.md#a-tree-in-not-so-many-bits)
- [Synchronous and Sequential Elements](wrinkles-in-time.md#synchronous-and-sequential-elements)
- [Sync/Seq Make a Tree](wrinkles-in-time.md#syncseq-make-a-tree)
- [Encode as a Succinct Bitstream](wrinkles-in-time.md#encode-as-a-succinct-bitstream)
- [Every Node Has a Unique Identifier](wrinkles-in-time.md#every-node-has-a-unique-identifier)
- [Topology Changes Change the Bits](wrinkles-in-time.md#topology-changes-change-the-bits)
- [Benefits of Topological Representation](wrinkles-in-time.md#benefits-of-topological-representation)
- [Topology vs. Coordinate Systems](wrinkles-in-time.md#topology-vs-coordinate-systems)
- [Applying Topology in Editorial Systems](wrinkles-in-time.md#applying-topology-in-editorial-systems)

## Chapter 5: Projection through a Topology
- [Time, From a Certain Point of View](wrinkles-in-time.md#time-from-a-certain-point-of-view)
- [Applications of Temporal Projection](wrinkles-in-time.md#applications-of-temporal-projection)
- [Foundations of Temporal Projections](wrinkles-in-time.md#foundations-of-temporal-projections)
- [Embedding Time Mappings in a Topology](wrinkles-in-time.md#embedding-time-mappings-in-a-topology)
  - [Properties of the Temporal Mapping Domain](wrinkles-in-time.md#properties-of-the-temporal-mapping-domain)
- [Measuring Time Across Discontinuous Intervals](wrinkles-in-time.md#measuring-time-across-discontinuous-intervals)
  - [Boundary Constraints in Projection](wrinkles-in-time.md#boundary-constraints-in-projection)
- [The Unit Identity Interval](wrinkles-in-time.md#the-unit-identity-interval)
- [The Nature of Topology Projection](wrinkles-in-time.md#the-nature-of-topology-projection)
  - [An Example](wrinkles-in-time.md#an-example)
- [Boundary Constraints](wrinkles-in-time.md#boundary-constraints)
- [Advanced Projections and Complex Topologies](wrinkles-in-time.md#advanced-projections-and-complex-topologies)
- [Non-Analytical Compositions through Approximation](wrinkles-in-time.md#non-analytical-compositions-through-approximation)
- [Practical Application: Composing Complex Functions](wrinkles-in-time.md#practical-application-composing-complex-functions)
- [Summary](wrinkles-in-time.md#summary)
- [About the Title](wrinkles-in-time.md#about-the-title)

## Chapter 6: Sampling Theory
- [In Which, The Rubber Hits The Road](wrinkles-in-time.md#in-which-the-rubber-hits-the-road)
- [The Continuous-Discrete Duality](wrinkles-in-time.md#the-continuous-discrete-duality)
  - [The Fundamental Challenge](wrinkles-in-time.md#the-fundamental-challenge)
  - [Definition of a Sampling](wrinkles-in-time.md#definition-of-a-sampling)
- [Sampling Functions in Time Algebra](wrinkles-in-time.md#sampling-functions-in-time-algebra)
  - [Mathematical Representation](wrinkles-in-time.md#mathematical-representation)
  - [Frequency Domain Perspective](wrinkles-in-time.md#frequency-domain-perspective)
- [Manipulating Samplings Through Projection](wrinkles-in-time.md#manipulating-samplings-through-projection)
  - [Transforming the Mapping, Not the Content](wrinkles-in-time.md#transforming-the-mapping-not-the-content)
  - [Remapping Example: Time Stretching](wrinkles-in-time.md#remapping-example-time-stretching)
  - [The Role of Phase in Sampling](wrinkles-in-time.md#the-role-of-phase-in-sampling)
- [Frame Kernels and Reconstruction](wrinkles-in-time.md#frame-kernels-and-reconstruction)
  - [The Frame Kernel Concept](wrinkles-in-time.md#the-frame-kernel-concept)
  - [Reconstruction of Continuous Signals](wrinkles-in-time.md#reconstruction-of-continuous-signals)
- [Resampling Techniques](wrinkles-in-time.md#resampling-techniques)
  - [Fetching New Samples](wrinkles-in-time.md#1-fetching-new-samples)
  - [Resampling with Convolution](wrinkles-in-time.md#2-resampling-with-convolution)
- [Continuous Parametric Sampling](wrinkles-in-time.md#continuous-parametric-sampling)
  - [Parametric Spaces and Worldlines](wrinkles-in-time.md#parametric-spaces-and-worldlines)
  - [Uniform Parametrization and Sampling Strategies](wrinkles-in-time.md#uniform-parametrization-and-sampling-strategies)
  - [Bridging Parametric and Temporal Spaces](wrinkles-in-time.md#bridging-parametric-and-temporal-spaces)
  - [Implications for Media Systems](wrinkles-in-time.md#implications-for-media-systems)
  - [Connecting to Topological Projection](wrinkles-in-time.md#connecting-to-topological-projection)
- [Practical Example: Retiming a Mixed Media Composition](wrinkles-in-time.md#practical-example-retiming-a-mixed-media-composition)
- [The Sampling Topology](wrinkles-in-time.md#the-sampling-topology)
  - [Continuous Representation of Discrete Samples](wrinkles-in-time.md#continuous-representation-of-discrete-samples)
  - [Transformations on Sampling Topologies](wrinkles-in-time.md#transformations-on-sampling-topologies)
- [Interpolation as Continuous Mapping](wrinkles-in-time.md#interpolation-as-continuous-mapping)
  - [Continuous Representation Through Interpolation](wrinkles-in-time.md#continuous-representation-through-interpolation)
  - [Interpolation Methods in Temporal Context](wrinkles-in-time.md#interpolation-methods-in-temporal-context)
- [Temporal Aliasing and Nyquist Limits](wrinkles-in-time.md#temporal-aliasing-and-nyquist-limits)
  - [The Nyquist-Shannon Sampling Theorem](wrinkles-in-time.md#the-nyquist-shannon-sampling-theorem)
  - [Dealing with Temporal Aliasing](wrinkles-in-time.md#dealing-with-temporal-aliasing)
- [The Sampling Function Taxonomy](wrinkles-in-time.md#the-sampling-function-taxonomy)
  - [Types of Sampling Functions](wrinkles-in-time.md#types-of-sampling-functions)
  - [Sampling Function Composition](wrinkles-in-time.md#sampling-function-composition)
  - [Coordinate Systems and Sampling](wrinkles-in-time.md#coordinate-systems-and-sampling)
  - [Topology and Sampling](wrinkles-in-time.md#topology-and-sampling)
  - [Projection and Sampling](wrinkles-in-time.md#projection-and-sampling)
- [Practical Example: SMPTE Timecode](wrinkles-in-time.md#practical-example-smpte-timecode)
  - [The Dual Nature of Timecode](wrinkles-in-time.md#the-dual-nature-of-timecode)
  - [Drop Frame vs. Non-Drop Frame: Timecode Compensation](wrinkles-in-time.md#drop-frame-vs-non-drop-frame-timecode-compensation)
  - [Historical Significance and Limitations](wrinkles-in-time.md#historical-significance-and-limitations)
  - [Revisiting SMPTE Timecode with Sampling Theory](wrinkles-in-time.md#revisiting-smpte-timecode-with-sampling-theory)
  - [From SMPTE to Temporal Algebra: A Path Forward](wrinkles-in-time.md#from-smpte-to-temporal-algebra-a-path-forward)
  - [Implementation Considerations](wrinkles-in-time.md#implementation-considerations)
- [Summary](wrinkles-in-time.md#summary-1)

## Chapter 7: Interactive Timelines
- [Indeterminancy, Observability, Many Worlds](wrinkles-in-time.md#indeterminancy-observability-many-worlds)
- [The Nature of Indeterminancy](wrinkles-in-time.md#the-nature-of-indeterminancy)
  - [The Messy Middle](wrinkles-in-time.md#the-messy-middle)
  - [Temporal Mapping of Indeterminate Intervals](wrinkles-in-time.md#temporal-mapping-of-indeterminate-intervals)
- [Multiple Temporal Domains](wrinkles-in-time.md#multiple-temporal-domains)
  - [The Layered Nature of Time in Interactive Media](wrinkles-in-time.md#the-layered-nature-of-time-in-interactive-media)
  - [Mapping Between Temporal Domains](wrinkles-in-time.md#mapping-between-temporal-domains)
  - [Temporal Domains in Practice](wrinkles-in-time.md#temporal-domains-in-practice)
  - [Indeterminancy Across Domains](wrinkles-in-time.md#indeterminancy-across-domains)
- [Observability](wrinkles-in-time.md#observability)
  - [The Collapse of Possibilities](wrinkles-in-time.md#the-collapse-of-possibilities)
  - [Handling Indeterminancy in Media Systems](wrinkles-in-time.md#handling-indeterminancy-in-media-systems)
- [Quantum Electrodynamics and Temporal Indeterminancy](wrinkles-in-time.md#quantum-electrodynamics-and-temporal-indeterminancy)
  - [Feynman's Perspective on Time](wrinkles-in-time.md#feynmans-perspective-on-time)
  - [Sum Over Histories](wrinkles-in-time.md#sum-over-histories)
  - [Temporal Entanglement](wrinkles-in-time.md#temporal-entanglement)
  - [Projection as Quantum Transformation](wrinkles-in-time.md#projection-as-quantum-transformation)
- [Physics Simulation in Temporal Algebra](wrinkles-in-time.md#physics-simulation-in-temporal-algebra)
  - [Bridging Simulation and Rendering Time Domains](wrinkles-in-time.md#bridging-simulation-and-rendering-time-domains)
- [Many Worlds](wrinkles-in-time.md#many-worlds)
  - [Branching Temporal Structures](wrinkles-in-time.md#branching-temporal-structures)
  - [Extending the Algebra to Graphs](wrinkles-in-time.md#extending-the-algebra-to-graphs)
  - [Projections Across Possible Worlds](wrinkles-in-time.md#projections-across-possible-worlds)
- [Applications to Interactive Media](wrinkles-in-time.md#applications-to-interactive-media)
  - [Real-time Interactive Systems](wrinkles-in-time.md#real-time-interactive-systems)
  - [Adaptive Media](wrinkles-in-time.md#adaptive-media)
  - [Continuous Simulation Systems](wrinkles-in-time.md#continuous-simulation-systems)
- [Practical Example: Interactive Music as Temporal Projections](wrinkles-in-time.md#practical-example-interactive-music-as-temporal-projections)
  - [The iMUSE System as an Implementation of Temporal Algebra](wrinkles-in-time.md#the-imuse-system-as-an-implementation-of-temporal-algebra)
  - [Markers and Hooks: Formalizing Indeterminancy](wrinkles-in-time.md#markers-and-hooks-formalizing-indeterminancy)
  - [Temporal Projections Through Musical Space](wrinkles-in-time.md#temporal-projections-through-musical-space)
  - [Compositional Implications: Authoring Potential Worlds](wrinkles-in-time.md#compositional-implications-authoring-potential-worlds)
  - [Practical Resolution of the "Messy Middle"](wrinkles-in-time.md#practical-resolution-of-the-messy-middle)
  - [Multiple Time Domains](wrinkles-in-time.md#multiple-time-domains-1)
  - [Mapping Interactive Narratives to Temporal Topologies: A Monkey Island Example](wrinkles-in-time.md#mapping-interactive-narratives-to-temporal-topologies-a-monkey-island-example)
  - [Application of H-Graph Methodology to Interactive Narrative](wrinkles-in-time.md#application-of-h-graph-methodology-to-interactive-narrative)
  - [Lessons for Modern Systems](wrinkles-in-time.md#lessons-for-modern-systems)
- [Conclusion](wrinkles-in-time.md#conclusion)

## Chapter 8: Temporal Algebra in Rendering Systems
- [The Intersection of Time and Light](wrinkles-in-time.md#the-intersection-of-time-and-light)
- [Multiple Temporal Domains in Rendering](wrinkles-in-time.md#multiple-temporal-domains-in-rendering)
  - [The Rendering Time Manifold](wrinkles-in-time.md#the-rendering-time-manifold)
- [Temporal Projection in Rendering](wrinkles-in-time.md#temporal-projection-in-rendering)
  - [Motion Blur as Temporal Integration](wrinkles-in-time.md#motion-blur-as-temporal-integration)
  - [Sampling Strategies for Temporal Integration](wrinkles-in-time.md#sampling-strategies-for-temporal-integration)
- [The Topology of Deformation](wrinkles-in-time.md#the-topology-of-deformation)
  - [Continuous Deformation as Temporal Projection](wrinkles-in-time.md#continuous-deformation-as-temporal-projection)
  - [Topology-Preserving Sampling](wrinkles-in-time.md#topology-preserving-sampling)
- [Physics Simulation in Rendering](wrinkles-in-time.md#physics-simulation-in-rendering)
  - [Simulation as a Temporal Projection Problem](wrinkles-in-time.md#simulation-as-a-temporal-projection-problem)
  - [Adaptive Timesteps and Interpolation](wrinkles-in-time.md#adaptive-timesteps-and-interpolation)
- [Temporal Antialiasing and Reconstruction](wrinkles-in-time.md#temporal-antialiasing-and-reconstruction)
  - [From Discrete Frames to Continuous Experience](wrinkles-in-time.md#from-discrete-frames-to-continuous-experience)
  - [Velocity Vectors and Temporal Reprojection](wrinkles-in-time.md#velocity-vectors-and-temporal-reprojection)
- [Shading and Time](wrinkles-in-time.md#shading-and-time)
  - [Temporal Coherence in Material Evaluation](wrinkles-in-time.md#temporal-coherence-in-material-evaluation)
  - [Causality in Light Transport](wrinkles-in-time.md#causality-in-light-transport)
- [Practical Implementation in Modern Renderers](wrinkles-in-time.md#practical-implementation-in-modern-renderers)
  - [Integration with Production Rendering Architectures](wrinkles-in-time.md#integration-with-production-rendering-architectures)
  - [Optimization Strategies](wrinkles-in-time.md#optimization-strategies)
  - [Case Study: Motion Blur in a Ray Tracer](wrinkles-in-time.md#case-study-motion-blur-in-a-ray-tracer)
- [Beyond Classical Rendering: Real-time and Interactive Systems](wrinkles-in-time.md#beyond-classical-rendering-real-time-and-interactive-systems)
  - [Temporal Reprojection in Real-time Rendering](wrinkles-in-time.md#temporal-reprojection-in-real-time-rendering)
  - [Temporal Upsampling and Interpolation](wrinkles-in-time.md#temporal-upsampling-and-interpolation)
- [Summary and Future Directions](wrinkles-in-time.md#summary-and-future-directions)
  - [Unified Temporal Framework for Rendering](wrinkles-in-time.md#unified-temporal-framework-for-rendering)
  - [Research Opportunities](wrinkles-in-time.md#research-opportunities)
  - [Conclusion](wrinkles-in-time.md#conclusion-1)

## Chapter 9: Applications
- [Rendering System Integration](wrinkles-in-time.md#rendering-system-integration)
  - [Temporal Algebra in 3D Rendering Pipelines](wrinkles-in-time.md#temporal-algebra-in-3d-rendering-pipelines)
- [Deform Operators Through the Lens of Temporal Algebra](wrinkles-in-time.md#deform-operators-through-the-lens-of-temporal-algebra)
  - [Bridging Temporal and Spatial Transformation](wrinkles-in-time.md#bridging-temporal-and-spatial-transformation)
  - [Mathematical Parallels](wrinkles-in-time.md#mathematical-parallels)
  - [Application Examples](wrinkles-in-time.md#application-examples)
  - [Implementation Considerations](wrinkles-in-time.md#implementation-considerations-1)
  - [Integration with Production DCC Tools](wrinkles-in-time.md#integration-with-production-dcc-tools)
- [Practical Implementation of Time Algebra](wrinkles-in-time.md#practical-implementation-of-time-algebra)
- [Examples of Time Algebra in Action](wrinkles-in-time.md#examples-of-time-algebra-in-action)
  - [Viewer Program with Sequential Clips](wrinkles-in-time.md#viewer-program-with-sequential-clips)
  - [Clipping Media](wrinkles-in-time.md#clipping-media)
  - [Overlapping Media](wrinkles-in-time.md#overlapping-media)
- [Beyond Simple Examples](wrinkles-in-time.md#beyond-simple-examples)
  - [Digital Content Creation (DCC) Systems](wrinkles-in-time.md#digital-content-creation-dcc-systems)
  - [Interchange Between Editorial Packages](wrinkles-in-time.md#interchange-between-editorial-packages)
  - [Theme Park Attractions](wrinkles-in-time.md#theme-park-attractions)
  - [Pipeline Integration](wrinkles-in-time.md#pipeline-integration)
  - [OpenTimelineIO Implementation](wrinkles-in-time.md#opentimelineio-implementation)
- [Benefits in Practice](wrinkles-in-time.md#benefits-in-practice)

## Conclusion
- [A New Foundation for Temporal Media](wrinkles-in-time.md#a-new-foundation-for-temporal-media)
- [Summary of Key Contributions](wrinkles-in-time.md#summary-of-key-contributions)
  - [Formalization of Temporal Domains](wrinkles-in-time.md#1-formalization-of-temporal-domains)
  - [Mathematical Framework](wrinkles-in-time.md#2-mathematical-framework)
  - [Natural-Rate Approach](wrinkles-in-time.md#3-natural-rate-approach)
  - [Practical Applications](wrinkles-in-time.md#4-practical-applications)
- [Benefits and Implications](wrinkles-in-time.md#benefits-and-implications)
  - [Technical Benefits](wrinkles-in-time.md#technical-benefits)
  - [Creative Benefits](wrinkles-in-time.md#creative-benefits)
- [Future Directions](wrinkles-in-time.md#future-directions)
- [Closing Thoughts](wrinkles-in-time.md#closing-thoughts)

## Appendices
- [Appendix A: Mathematical Reference](wrinkles-in-time.md#appendix-a-mathematical-reference)
  - [A.1 Affine Transformation Matrices](wrinkles-in-time.md#a1-affine-transformation-matrices)
  - [A.2 Allen's Interval Algebra Relations](wrinkles-in-time.md#a2-allens-interval-algebra-relations)
  - [A.3 Time Sampling Functions](wrinkles-in-time.md#a3-time-sampling-functions)
- [Appendix B: Glossary of Terms](wrinkles-in-time.md#appendix-b-glossary-of-terms)
- [Appendix C: Survey of Contemporary Editing Systems](wrinkles-in-time.md#appendix-c-survey-of-contemporary-editing-systems)
  - [C.1 Avid Media Composer](wrinkles-in-time.md#c1-avid-media-composer)
  - [C.2 Adobe After Effects](wrinkles-in-time.md#c2-adobe-after-effects)
  - [C.3 OpenTimelineIO](wrinkles-in-time.md#c3-opentimelineio)
- [Appendix D: Code Examples](wrinkles-in-time.md#appendix-d-code-examples)
  - [D.1 Basic Data Types](wrinkles-in-time.md#d1-basic-data-types)
  - [D.2 Implementing Affine Time Transformation](wrinkles-in-time.md#d2-implementing-affine-time-transformation)
  - [D.3 Interval Operations](wrinkles-in-time.md#d3-interval-operations)
- [Appendix E: Resources and Further Reading](wrinkles-in-time.md#appendix-e-resources-and-further-reading)
  - [E.1 Mathematical Foundations](wrinkles-in-time.md#e1-mathematical-foundations)
  - [E.2 Media Systems](wrinkles-in-time.md#e2-media-systems)


# Introduction

## Time in Media Composition Systems

The representation and manipulation of time is a core challenge in media composition systems. From traditional film editing to modern digital content creation, artists and technologists have grappled with the complexities of representing, transforming, and presenting time-based media.

Contemporary media composition involves working with disparate elements that each have their own internal temporal logic. Video clips can have different frame rates, audio has independent sampling rates, and visual and auditory elements must somehow be composed together on a unified timeline for presentation.

## Historical Context

In the very beginning of the creation of timed media, time was an aspect of authorial agency; the time base itself dictated by the speed an operator cranked the shutter and the film through the aperture (Figure 1). Films were distributed with time scores that instructed the projectionist how fast to advance the film during scenes, and what part of the score a pianist should play when. The display of the movie was orchestrated on the fly by the projectionist and musician.

![Figure 1](assets/17470253273752.jpg)
***Figure 1:** Time in the silent era.*

This all changed with the introduction of sound. The audio track was optically printed alongside the film cells and so the film had to advance at a constant rate to ensure synchronization. Many innovations were centered on how to plan synchronization for animated films, as seen in Figure 2, a diagram from US 1,941,341- April 2, 1933 by Disney.

![Figure 2](assets/17470259330957.png)
***Figure 2**: Synchronizing sound with images.*

In another invention, the perforations where used to trigger a click in headphones so that musicians could keep precise base with the planned beats, as show in Figure 3.

![Figure 3](assets/17470264682794.png)
***Figure 3**: A method to synchronize human performers to the film score.*

Fundamentally though, the contemporary to time in media systems has its roots in the edit bay. Rolls of film for images and reels of magnetic tape for sound were gathered at the end of a day of shooting, the film was developed and processed. Once the film was developed, the audio was registered with the image frames by transfer to a "mag track." For 35mm film with four perforations per frame, the mag track was recorded at a speed where each four perforations corresponded to 1/24 of a second of sound.

The synchronization process used several key elements:

- A clapper was recorded at the beginning of each take
- A frame was marked on the film where the clapper boards first visually meet
- The audio was matched to the film so the peak in the audio recording corresponded to the marked frame
- The perforations in the film and audio track provided the increments for synchronization
- Edge codes (numbers embossed on film) served as numeric indices for frames

Figure 4 illustrates some of these elements.

![Figure 4](assets/17469118335146.jpg)
***Figure 4**: A film clip showing image and sound.*

This synchronization process was accurate to within 1/96 of a second for standard 24fps film. The edge codes allowed editors to verify sync throughout the editing process, and every subsequent print would photographically transfer these codes, ensuring the correspondence was never lost. Figure 5 shows an analog computer that embossed edge codes on film.

![Figure 5](assets/17470273425020.jpg)
***Figure 5:** This machine embosses edge codes on film.*


These mechanisms found application beyond film.  They could control elements in rides and animatronics, as illustrated in Figure 6, depicting a rocket ship ride.

![Figure 6](assets/17470261360092.png)
***Figure 6**: A rocket ship ride with synchronized elements.*

Mechanical film editing systems, such as the Moviola, allowed editors to physically cut printed takes and join them together with adhesive to create a "cut." For overlapping effects like dissolves, a diagonal cut was made in the film segments, which were then joined along this line. Throughout this process, take names and edge codes ensured that source materials could be identified and utilized by the optical laboratory responsible for creating the "answer print" - the final form of the film.

Throughout this meticulous process, source materials maintained synchronization through a fixed sampling rate and edge codes that dictated exact correspondence between media. An "edit decision list" (EDL) functioned as a recipe to produce an answer print given a library of sources, edge code ranges, and effect types. These EDLs were originally written by hand on paper.

The transition to video tape and digital non-linear editing revolutionized this process. Time codes in video served the same role as film's edge codes, and edit decision lists directed the queuing of video portions rather than photographic composites. Systems like EditDroid (introduced in 1984) replaced video tapes with source material on laserdisc, allowing random access to footage through computer interfaces. Throughout the 1990s, playback and recording systems improved until the editing process converged on what might be considered an emulation of the film editing paradigm.

This organic evolution gave rise to modern non-linear editing systems, which at their core still represent a bin of film strips layered in rows that represent the order of composition, indexed by fixed sample rate frame codes.

## The Current Challenge

Despite technological advances in playback and encoding, modern non-linear editing systems still fundamentally represent their document models according to traditional, analog workflows. Media composition still deals with "film strips" layered in rows that represent the order of composition, indexed by fixed sample rate frame codes. Figure 6 shows a film editing table with film strips arrayed in aluminum tracks. Anyone familiar with a modern NLE will immediately grasp the metaphors still in use today.

![Figure 7](assets/17470274807356.jpg)
***Figure 7:** A historic film editing table.*

However, this paradigm is increasingly insufficient for contemporary media needs. Modern production may involve:

- Film shot at over 100 frames per second
- Video at various frame rates (multiples of 30 or 25 fps)
- North American broadcast video at NTSC rates (e.g., 29.97 fps = 30 * 1000/1001)
- Audio at various sampling rates (44.1kHz, 48kHz, etc.)
- Arbitrary precision in temporal composition

Contemporary editing systems attempt to resolve these disparate rates by imposing workflow restrictions. For example, media might need to be transcoded or "rendered" to conform to a project's frame rate, creating generational data loss in the process.

## A New Approach

This book proposes a fundamental rethinking of how time is represented in media composition systems. By applying principles from mathematics, computer graphics, and sampling theory to the temporal domain, we can develop a more robust framework for working with time.

The approach treats time as a one-dimensional normed vector space subject to mathematical operations familiar from other domains. Just as 3D computer graphics leverage hierarchical coordinate systems for better precision and control, we can apply similar principles to the temporal dimension.

The following chapters will explore this new temporal algebra in detail, from its mathematical foundations to its practical applications in next-generation media composition systems.

# Chapter One: Media Composition Time Challenges

## The Problem of Multiple Temporal Rates

At the heart of media composition lies a fundamental challenge: integrating media elements that operate at different temporal rates. Consider a typical production scenario:

- Video clips may have their own frame rates (24fps, 25fps, 30fps, 60fps, etc.)
- Audio operates at a completely independent sampling rate (44.1kHz, 48kHz, 96kHz)
- Different elements may undergo rate changes (speed ramps, time warps, etc.)

In such scenarios, mapping clip frames and audio signals to presentation frames becomes increasingly complex. The traditional assumption that time can be treated as strictly linear breaks down when faced with:

- Warping and temporal subsampling operations
- Real data that is aperiodic in nature
- Media that needs to be composed on a consistent timeline

## Today's Conform-Based Workflow

The current paradigm in most non-linear editing systems relies on a "conform"-based workflow in which all media is conformed to a fixed project rate (usually based on the primary intended output rate). Figure 8 illustrates this rigid pipeline that prioritizes conformity over fidelity.

![Figure 8](assets/17469130234241.jpg)
***Figure 8**: Today's conform-based workflow where all media is resampled to match a fixed project frame rate.*

1. All media must conform to a fixed project frame rate (typically 24fps)
2. Incoming media is resampled/converted to match this fixed rate
3. The composition is built at this fixed rate
4. The final result is rendered at this same fixed rate

This workflow enforces a rigid temporal structure that simplifies many engineering challenges but introduces significant limitations. Media must be transformed, often losing quality in the process, to fit into this predetermined framework.

## Problems with the Conform-Based Approach

The conform-based workflow presents several critical issues:

1. **Quality Degradation**: Each time media is resampled to conform to a different rate, some information is inevitably lost. This can manifest as visual artifacts, audio distortion, or subtle timing issues.

2. **Precision Loss**: As explored in depth in "Ordinate Precision Research," conforming operations lead to precision loss in time information throughout a project's lifespan.

3. **Workflow Inefficiency**: Artists must wait for media to be conformed before they can work with it, creating bottlenecks in the creative process.

4. **Limited Expressivity**: Creative time-based effects are constrained by the uniform temporal framework.

5. **Technical Debt**: Systems incorporate various heuristics and ad-hoc exceptions to overcome the limitations of the conform-based approach, leading to increasing complexity and fragility.

## Tomorrow's Natural-Rate Based Workflow

As shown in Figure 9, a natural-rate based workflow approach inverts the traditional conform-based paradigm.

![Figure 9](assets/17469130420932.jpg)
***Figure 9**: Tomorrow's natural-rate based workflow where media maintains its native temporal rate until final presentation.*

1. Media exists in its native temporal rate (creating a "natural rate bin")
2. The composition operates in continuous time rather than at a fixed frame rate
3. Import processes place media in this continuous timeline
4. Rendering/presentation samples this continuous representation as needed

Instead of forcing all media to conform to a single rate early in the process, the original temporal information until the final presentation stage.

## Benefits of the Natural-Rate Approach

A natural-rate workflow offers several key advantages:

1. **Preservation of Information**: Media retains its original temporal characteristics throughout the editorial process.

2. **Flexibility**: The system can more easily accommodate new media types with diverse temporal characteristics.

3. **Higher Quality**: By postponing sampling decisions until the final output stage, the highest possible quality can be maintained.

4. **Mathematical Rigor**: The approach is built on a foundation of well-understood mathematical principles rather than heuristics and special cases.

5. **Futureproofing**: As new media formats emerge with different temporal characteristics, the system can incorporate them without fundamental redesign.

The following chapters will explore the mathematical foundations and practical implementation of this natural-rate approach, providing a comprehensive framework for next-generation media composition systems.


# Chapter Two: Domains of Time

## The Wheel of Creation

Media production can be visualized as a cyclical process involving distinct temporal domains. This "Wheel of Creation" encompasses the full lifecycle of media, from its inception in the real world to its presentation to an audience and potentially back again through interactive participation.

At its core, we are breaking the continuity of space and time to create a narrative world. This process involves transformations across multiple temporal domains, each with its own characteristics and purpose. The cyclical nature of these transformations can be visualized as a 'Wheel of Creation' (Figure 10).

<!-- may also want to include a note that the temporal properties of each step along the wheel is either endogenous (inherent in what is being recorded or performed) or exogenous (being imposed externally) - there is a lot of discussion of that quality but it doesn't get called out up front -->

![Figure 10](assets/17469117329836.jpg)
***Figure 10**: The Wheel of Creation - A cyclical representation of media production domains showing the transformation of time through the creative loop.*

<!-- todo: needs an image?  The leap from "wheel of creation" to "the production loop" feels abrupt.  Maybe a sentence to connect this to the "wheel of creation" image?  The next section has an image with the cut of the wheel that helps connect it back. -->

## The Production Loop

The production loop represents the complete cycle of media creation, composition, and presentation. Understanding the distinct temporal domains within this loop is essential for developing a comprehensive time algebra.

Let's examine each domain in detail:

### Narrative Time

Narrative time is an *endogenous* abstract temporal domain where story events are ordered. This is the time experienced by characters within a story—the *diegetic* time in which footsteps synchronize with walking characters or where the internal logic of a simulation unfolds.

Narrative time may be hierarchical. For example, a piece of music played by an orchestra filmed for a movie has its own narrative time embedded within the film clip's action time.

### Capture Time

Capture time is an *exogenous* continuous domain occurring in the real world. This is the physical time in which cameras record scenes, microphones capture sound, or sensors record motion.

A scene is transformed from exogenous capture time to narrative time through the capture process, producing the raw media that will later be composed.

### Media Time

Media time is an *endogenous* domain that enumerates frames or discrete samples of media. This domain is typically periodic, with regular intervals between samples, though it doesn't have to be.

Media itself is indexed, often by frame numbers. Sampling functions, explored later, convert between narrative time and media time, retrieving particular frames or samples.

### Composition Time

Composition time is the domain where objects are arranged onto a timeline. In a non-linear editor, this is typically a discrete, periodic domain.

This is the time domain that editors work in directly, arranging clips, applying effects, and creating the structure of the final piece.

### Presentation Time

Presentation time is a discrete, aperiodic, exogenous domain—the times at which images are refreshed for presentation to an audience.

This domain represents the actual moments when frames are displayed on screen or audio samples are played through speakers. Importantly, this may not align perfectly with the original composition time due to various factors in the display system.

### Observation Time

Observation time is a bridging domain between presentation time and the continuous exogenous domain the audience experiences.

This represents the perceptual time of the viewer—how they experience the presented media as a continuous flow despite the discrete nature of the presentation.

### Participation Time

Participation time bridges the exogenous, continuous participant time with the endogenous, discrete, aperiodic domain corresponding to sensor sampling steps.

In interactive media, this domain captures how user inputs are sampled and integrated into the system.

### Generation Time

Generation time is the domain where interactive input is associated with dynamic objects. This is a discrete, aperiodic domain corresponding to engine or simulation time steps.

In game engines or interactive experiences, this is where user inputs are processed to generate new content or states.

### Reification Time

Reification time is associated with the recording of generated data. This is a discrete, typically periodic domain for dynamic composition.

This domain represents the process of capturing or "making real" the results of interactive generation for later use.

### Rendering Time

Rendering time is associated with the rendering of reified data. This is also a discrete, typically periodic domain for dynamic composition.

This domain represents the process of transforming composed elements into presentable media frames.

## The Real-Time Loop

![Figure 11](assets/17469119177127.jpg)
***Figure 11**: The real-time interactive production loop, highlighting the immediate coupling between composition and creation.*

In real-time interactive systems, the production loop operates without the media capture step (Figure 11). The composition domain in this case is not an editorial timeline but a render composite layer.

The composition domain becomes discrete and aperiodic, bridging the rendering and presentation domains in a possibly trivial manner.

## Relationships Between Domains

Understanding how these temporal domains relate to each other is key to developing a comprehensive time algebra. Each domain transformation introduces specific challenges and mathematics to formalize the operations.

The domains form a directed graph of transformations, where each edge represents a mathematical function that converts time from one domain to another. Some of these transformations are straightforward and lossless, while others involve sampling, resampling, or other operations.

In the following chapters, we will develop the mathematical foundations needed to formalize these domain transformations and build a robust algebraic framework for working with time across the entire production loop.


# Chapter 3: Mathematical Foundations of Time

## Kripke Semantics and the Logic of Time

Modern temporal logic has its roots in Saul Kripke's semantics, a model-theoretic framework originally devised to formalize modal concepts like necessity and possibility (Kripke 1961). A Kripke model describes a network of “possible worlds,” connected by an accessibility relation—a structure that determines which worlds are reachable from which others. When applied to time, these worlds become moments, and the accessibility relation encodes temporal ordering.

In this view, a temporal statement such as "*eventually A*" becomes a logical assertion about the reachability of a world in which *A* holds, given the structure of time. Thus, Kripke-style temporal logic treats time as a structured set of points, each representing a discrete moment, often embedded within a graph-like frame. Temporal logics of this kind—sometimes linear, sometimes branching—define their modal behavior over these time points using operators like *next*, *until*, and *always*.

A foundational work in this tradition is Johan van Benthem’s *The Logic of Time: A Model-Theoretic Investigation into the Varieties of Temporal Ontology and Temporal Discourse* (1983, revised 1991). Van Benthem’s work provides one the most comprehensive and influential formalisms for temporal reasoning—a model that subsequent developments in temporal logic, computation, and formal semantics have drawn upon extensively. His analysis explores the expressive power of modal languages over different temporal structures and axiomatizes the behavior of time from a semantic standpoint, within the point-based paradigm inherited from Kripke.

However, the point-based perspective—though elegant and powerful for many domains—presents limitations when applied to media systems and interactive processes. These systems require reasoning not only about when events occur, but for how long they persist, how they overlap, and how they compose over intervals. In such contexts, time cannot be treated merely as a sequence of indivisible instants. Rather, it must be understood as a duality between the discrete and the continuous, as formalized in sampling theory and expressed through interval-based models of time.

Later chapters will return to Kripke’s many-worlds semantics to explore branching time, modal narratives, and interactive futures. But for now, we begin by setting the stage with a more geometrical and algebraic foundation for time.

## From First Principles

*Tempus est fluxus; et rationem ejus in punctis colligere fallacia est.*

<!-- citation / translation for the latin? ^ -->

To construct a rigorous framework for temporal operations in media systems, we must first define time from mathematical first principles. This chapter establishes the foundational mathematical concepts that are needed for the development of a temporal algebra.

<!-- I think its worth noting, whether here or earlier in the book, that we're basing this on the human EXPERIENCE of time, and not necessarily on an experimental external-to-human experience nature of time. In other words, we're not seeking here to build a version of time that is axiomatic or experimentally supported or in some way representing a physical truth about how time functions; rather this is about how humans experience time and in particular how time functions in art and in how humans experience time based media/art. I'm not sure what the exact right way to frame that is, but basically we didn't go and smash atoms or something to do this, we thougth about and looked at how people use time in entertainment and how the systems that support those kinds of projects represent time.  That isn't to say that our system is somehow in opposition to how time may or may not "really" function in the physical world or in a scientific sence, its only to say that wasn't the destination we were heading for.  

In particular the comment about time having a direction and being monotonic - if quantum nonsense makes this no longer true, it won't violate the way we percieve time to work at the scale of our experience and in the domain of our art. -->

## Define a Metric Space

A time line is a monotonically increasing metric space, implying several important characteristics:

1. Time has a direction, it monotonically increases
2. It has a metric: distance can be measured between two points in time
3. Time has a unit measure with non-zero length, named e₀
4. e₀ = e₀ * e₀ (the unit is self-consistent)

To treat time as a metric space in the Euclidean sense, we must first define a unit of measure. We introduce a unit time interval e₀, not as a physical quantum of time, but as a geometric norm that imparts dimensional structure to the otherwise pure topology of the timeline. This construction mirrors Euclid’s use of a unit line segment to establish measurement within a continuum. Once such a unit is defined, any scalar multiple of e₀ yields meaningful, measurable durations—including frame intervals, tick rates, or sample steps—without imposing a fixed discretization. Importantly, the identity e₀ = e₀ × e₀ expresses not a dimensional paradox, but a consistency of scale: a duration remains invariant under self-scaling in the temporal algebra, much like the multiplicative identity in a normed space. This fundamental property is visualized in Figure 12.

![Figure 12](assets/17469119889101.jpg)
***Figure 12**: Time as a metric space with unit measure e₀, showing the relationship between adjacent time points.*

## Time as an Ordinate and Separating Plane

<!-- This section is written with "Time" as the primary noun, which previously described the medium/continuum.  I think the point here is important about using a point vs a half plane as the base construct, but maybe this should be "Present Time" or "A moment in time", "point in time", "instant in time"? Or is the point here that time is not the continuum itself but rather half plane which separates that which has happened from what hasn't happened yet?  -->

Time is conventionally considered an ordinate - a location on a coordinate axis (see Figure 13).

![Figure 13](assets/17469121386125.jpg)
***Figure 13**: Conventional representation of time as a location on a one-dimensional coordinate axis.*

Rather than treating time merely as an abstract axis, we model it geometrically as an infinite half-plane separating the past and the future (Figure 14). It is bounded on one side by the present and extends indefinitely into both past and future. This structure admits rigorous interpretations in the domains of signal analysis and causal reasoning. In time-frequency representations, for instance, signals are often restricted to causal half-planes where energy is nonzero only after a given time origin. Likewise, in relativistic systems and wavefront propagation, causal cones partition spacetime in a way that resembles a half-plane separating the known from the indeterminate. In the context of this derivation, the half-plane formulation provides both a visual and analytic tool to reason about the orientability, coverage, and continuity of time as it underlies sampled, layered, or interactive media systems.

![Figure 14](assets/17469120885940.jpg)
***Figure 14**: Time represented as an infinite half-plane that separates the past from the future.*

A timeline can be covered by any number of intervals, and always covers [-∞, +∞). This coverage property is important for ensuring that the temporal algebraic operations are complete. Figure 15 shows multiple right-met intervals spanning the entire timeline.

<!-- I feel like "right-met" ^ is a distracting fact in this sentence.  the point isn't what kind of intervals they are, merely that they cover the entire timeline.  But I defer to you here. the next section also opens with "right-open" rather than "right-met". -->

![Figure 15](assets/17469121911540.jpg)
***Figure 15**: A timeline covered by multiple intervals spanning from negative infinity to positive infinity.*


## Intervals

In this framework, intervals are right-open (inclusive on the left, exclusive on the right), though they may have an infinitesimal length ever so slightly greater than zero. If length is zero, the endpoints are equal, and therefore the interval is empty because an interval can't both include and not include the same point.

This definition of intervals provides a clean foundation for operations on time segments without edge cases or ambiguities at the boundaries.

<!-- does this require any further elaboration, proof or citation? ^ it feels a bit thrown out there but maybe its elementary enough to not require further elaboration.  It isn't obvious though - we had to think about it (each time). -->

## Coordinate Systems & Topology

### Interval Algebra

James F. Allen introduced a calculus for temporal reasoning in 1983, which provides a complete set of predicates to describe how intervals relate to each other. Allen's interval algebra defines the following fundamental relations between two intervals:

1. **Before/After**: One interval completely precedes the other
2. **Meets/Is Met By**: One interval ends exactly where the other begins
3. **Overlaps/Is Overlapped By**: The intervals overlap partially
4. **During/Contains**: One interval is completely within the other
5. **Starts/Is Started By**: The intervals share a starting point, but one ends before the other
6. **Finishes/Is Finished By**: The intervals share an ending point, but one starts after the other
7. **Equals**: The intervals are identical

Figure 16 illustrates these fundamental relations. They are pairwise disjoint and exhaustive, in that any two time intervals must be related by one of these relations.

![Figure 16](assets/17469123800935.jpg)
***Figure 16**: Allen's interval algebra depicting the fundamental relations between two time intervals.*

<!-- ^ this figure should get number labels for each of the relations, or the annotation should note the order in which the relations are present in the image.  Also, this image depicts right-met intervals, but IIRC Allen doesn't deal with clusivity (which is an important point made in the next paragraph).  In that way this image does NOT illustrate allen's algebra.  -->

We extend Allen's interval algebra to consider the clusivity of points (whether endpoints are inclusive or exclusive). As an example, if both endpoints are considered inclusive, if the end of one interval and the beginning of the other have the same value, the intervals actually overlap rather than meet. The temporal algebra stipulates right-open intervals (see: [Intervals](#Intervals)) -- the beginning of the interval is inclusive, and the end is exclusive -- if the end of the first interval and the beginning of the second interval have the same value, the intervals meet, but the point of meeting is only within the bounds of the second interval. This allows us to create bijective mapping of timelines where every point in one temporal manifold maps to a unique point in another.

<!-- Does that last sentence require elaboration?  Its not immediately obvious to me why right-met is the only constraint that needs to be met in order to create a bijective mapping, and I dont't think the word "manifold" has appeared in the document so far. -->
.
```
Given:
I1 [t0, t1)
I2 [t1, t2)

and t0 < t1 < t2

Then t1 is a bound for both I1 and I2, but only within the bounds of I2.
```

### Affine Transformations

The same mathematics from linear algebra that works for 3D and 2D coordinate systems can be applied to 1D timelines. Affine transformations can be represented with homogeneous coordinates:

```
[ S P ]
[ 0 1 ]
```

Where:
- S = Scale
- P = Position

For example, to transform from origin O₁ to origin O₂, where O₂ is O₁ + 10:

```
[ 1 10 ]
[ 0  1 ]
```

This transformation matrix allows us to convert coordinates from one temporal space to another, and these transformations can be composed through matrix multiplication.  The other properties of affine transformation that apply to one dimensional spaces also apply here.

<!-- citation or elaboration? ^  -->

### Change of Basis Transformation

In media composition, we frequently need to transform between different temporal coordinate systems. Figure 17 illustrates some of the many coordinate systems we frequently need to transform between.

![Figure 17](assets/17469125340295.jpg)
***Figure 17**: Multiple temporal coordinate systems illustrated, showing many possible coordinate systems between the presentation timeline and capture time.*


1. **Local time**: The timeline within a clip (e.g., 0-380 frames)
2. **Normalized local time**: The clip timeline normalized to 0-1
3. **Media time**: The original media's timeline (e.g., 3000-4003100)
4. **Capture time**: The real-world time when the media was captured (e.g., 16:14:00-16:14:05.167)
5. **Presentation time**: When the media is presented (e.g., 86500-86880)
6. **Normalized presentation time**: Presentation time normalized to 0-1

The affine transformation matrices allow us to convert between any of these coordinate systems, maintaining precise temporal relationships throughout. Figure 18 demonstrates how these transformations affect the time domain.

![Figure 18](assets/17469124835118.jpg)
***Figure 18**: Affine transformation applied to time coordinates, demonstrating how scale and position parameters modify the time domain.*


## Normed Vector Spaces & Intervals

By treating time as a normed vector space subject to manipulation through linear algebra, we can leverage the power of mathematical operations that are well understood in other domains.

This approach allows us to:

1. Maintain precision throughout complex transformations
2. Compose operations in a predictable and invertible manner
3. Reason rigorously about temporal relationships
4. Apply the rich set of tools from linear algebra to temporal problems

The affine transformation approach also provides better numerical precision, artistic control, and flexibility—similar to how hierarchical coordinate systems function in 3D computer graphics.

<!-- I feel like something should go here about  sampling theory,which establishes the basis of the observation that up until this point we've been talking about continuous time, however most if not all of the media that is handled by computer systems is discreetly sampled.  Pointing out that these tools satisfy the requirements to have sampling theory function in this domain.  Its mentioned in the next section and feels a bit discontinuous to me. -->

## Time Algebra Elements and Operations

To construct the complete time algebra, we define the following fundamental elements:

1. **Time Points**: Unique temporal coordinates with no extent
2. **Time Intervals**: A pair of time points bounding a segment of time
3. **Samplings**: Sets of time points
4. **Media**: Elements of composition, indexable by time points

With these elements, we can define several classes of operations:

1. **Operations over time**: Functions that take time as an argument and return new time
2. **Operations over intervals**: Functions that take time intervals and return new intervals
3. **Sampling Functions**: Functions that take time intervals and return samplings
4. **Operations on Samplings**: Functions that take samplings and return new samplings
5. **Media Functions**: Functions that take samplings and media as arguments and return media

## Summary

This algebraic framework provides a formal foundation for all the temporal transformations required in media composition systems, from simple edits to complex interactive experiences. It draws on well-established mathematical structures—but the derivation from time as a half-space towards an interval-based algebra reflects a distinct and purposeful synthesis that is not entirely conventional.

<!-- I get what you're going for here with this summary but I feel like the document might be better served by a more holistic summary that restates the big bullet points of all the foundational things (IE, half plane, right met) rather than focusing on what is or is not novel in this approach. -->

### The Conventional

1. Time as a metric space: This is a standard mathematical abstraction—time as a totally ordered, continuous or discrete, real-valued space with a metric is widely used in physics, computer science, and formal semantics.
2. Affine transformations and coordinate systems: The use of affine transformations to move between coordinate systems is standard in animation, signal processing, and media systems.
3. Allen’s interval algebra: This is a canonical reference point in AI and temporal reasoning literature. Extending it to explicitly deal with clusivity and right-open intervals is common in temporal databases and digital systems.

### The Novel

1. Time as a half-plane separating past and future: This is not standard phrasing. Most treatments speak of time as a line, sometimes oriented, but the use of the half-plane metaphor introduces a topological and epistemic metaphor—a conceptual boundary between knowable past and potential future. This connects evocatively to modal logic and temporal epistemology.
2. The synthesis from Kripke-style point-based logic to an algebra over intervals: We intentionally start from a point-based perspective (via Kripke/van Benthem) and showing that this is insufficient for media and interactive systems, hence moving to an interval-based, compositional, algebraic framework. This perspective serves as something of a critique of the limitations of point-based temporal logics in modeling sampled, continuous media systems.
3. Right-open intervals with unit measure and self-consistency (e₀ = e₀ * e₀): This axiom is unconventional in its form, and recalls the spirit of defining temporal quanta in a computational or physical system. Most interval algebras don’t explicitly introduce this kind of unit identity element, as they don't invoke a metric.
4. Sampling theory as a fundamental reason for needing interval-based logic: Traditional logic does not deeply engage with sampling theory or the duality between continuous and discrete representations. The treatment here is closer in spirit to signal processing, media systems design, and temporal epistemology (e.g., the ontological distinction between "event" and "duration").

While this chapter has treated time primarily as a one-dimensional metric space enriched with algebraic structure, the needs of interactive and compositional media demand a more general foundation. Time in such systems often flows through nested, looping, and concurrent paths—structures that defy simple linear or even branching models. To address these complexities, we turn next to topological and manifold-based treatments of time. Chapter 4 extends the current algebraic frame into a broader geometric context, introducing temporal manifolds, continuity classes, and topological invariants that enable rigorous modeling of complex, multi-resolution, and non-Euclidean timelines.

# Chapter 4: Temporal Topology

## A Tree, In Not So Many Bits

The structure of a media composition can be represented topologically as a hierarchy of nested temporal elements. This chapter explores how we can represent the temporal topology of a composition efficiently and expressively.

## Synchronous and Sequential Elements

Topologically, a composition consists fundamentally of two kinds of temporal relationships:

1. **Synchronous Starts**: Elements that begin at the same time
2. **Sequential Starts**: Elements that begin one after another

Figure 19 shows a typical timeline structure with both synchronous and sequential relationships.

![Figure 19](assets/17469125705363.jpg)
***Figure 19**: A composition timeline showing tracks with synchronous and sequential media elements.*


For example, in a typical timeline, we might have:
- An audio track with elements: Gap → SW001 → SW002 → SW009
- A picture track with elements: SW003 → SW004 → Gap
- Another picture track with: Gap → SW005 → SW002 → SW002 → SW005-pip

These elements form a complex temporal structure, but at their core, they're organized through these two fundamental relationships.

## Sync/Seq Make a Tree

We can represent these relationships using a tree structure, where:
- A "sync" node groups elements that start synchronously
- A "seq" node groups elements that start sequentially

Figure 20 illustrates the synchronous starts in the sample timeline, and Figure 21 shows the sequential starts.

![Figure 20](assets/17469126172566.jpg)
***Figure 20**. The synchronous starts in the sample timeline.*

![Figure 21](assets/17469127531920.jpg)
***Figure 21**. The sequential starts in the sample timeline.*


For example, a composition might be represented as:

```
(define composition
   (sync domain picture
     (seq gap (sync sw005
                    sw005-pip) sw006 sw007 sw008))
     (seq sw003 sw004)
     (seq domain audio
          gap sw001 sw002 sw0009))
```
This structure is visualized in Figure 22, where each branch represents a temporal relationship.

![Figure 22](assets/17469128774337.jpg)
***Figure 22**: Composition tree with explicit sync and seq nodes highlighting the temporal organizational structure.*


This tree structure creates a hierarchical representation of the temporal relationships in the composition.

## Encode as a Succinct Bitstream

A succinct bit encoding of a binary tree is a pre-order traversal typically storing a 1 when a node exists and 0 otherwise. This yields an O(n) time and space encoding of a tree. Taking inspiration from that we encode the tree structure of a timeline as a succinct bitstream, where:

- The root is 1
- Sync starts are 0
- Sequential starts are 1

We append zeroes to indicate nodes that synchronously start from the current node, and we append ones to indicate nodes that start sequentially. Unlike a conventional succinct encoding, this scheme embues additional information. Given the code of a node, it's entire history is explicitly visible, as is its status of being a synchronous start or not.

Figure 23 demonstrates this efficient encoding scheme applied to an example composition tree.

![Figure 23](assets/17469129264672.jpg)
***Figure 23**: Succinct bitstream encoding of the composition tree where 1 represents the root, 0 represents sync starts, and 1 represents sequential starts.*


This encoding provides a highly efficient representation of the temporal topology.

## Every Node Has a Unique Identifier

Using this bitstream encoding, every node in the tree has a unique identifier that encodes its path from the root. This provides several advantages:

1. Parents and common ancestors are easily determined
2. The immediate parent of SW009 (10001111) is 1000111 (SW002)
3. Relationships between elements can be quickly computed

## Topology Changes Change the Bits

If the topology of the composition changes (e.g., elements are rearranged), the bitstream encoding changes accordingly. However, the paths remain unique, even though some have changed.

For example, if SW002 and SW009 move to different positions in the tree, their bitstream identifiers become 10011 and 100111 respectively.

## Benefits of Topological Representation

This topological approach to representing time in media compositions offers several advantages:

1. **Efficiency**: The bitstream encoding is extremely compact
2. **Expressivity**: Complex temporal relationships can be represented clearly
3. **Computation**: Operations on the temporal structure become algebraic operations on the bitstream
4. **Flexibility**: The representation accommodates both linear and non-linear temporal structures

## Topologies vs. Coordinate Systems

This topological representation complements the coordinate system approach discussed in the previous chapter:

- **Coordinate Systems** provide precise positioning within a temporal context
- **Topology** provides the structural relationships between temporal elements, and a place where metrics may be joined

Together, these two approaches form a complete framework for representing and manipulating time in media composition systems.

## Applying Topology in Editorial Systems

The topological representation enables several powerful capabilities in editorial systems:

1. **Efficient Storage**: The succinct bitstream encoding minimizes storage requirements
2. **Fast Queries**: Determining temporal relationships becomes a simple operation on bitstreams
3. **Change Tracking**: Modifications to the temporal structure result in predictable changes to the bitstream
4. **Hierarchical Operations**: Operations can be applied to entire subtrees with a single transformation

This topological approach provides a strong foundation for representing the temporal structure of complex media compositions, complementing the coordinate-based transformations discussed in previous chapters.

# Chapter 5: Projection through a Topology

## Time, From a Certain Point of View

In previous chapters, we established the mathematical foundations of time as a normed vector space and explored the topological representation of temporal structures in media compositions. This chapter extends these concepts to examine how time can be projected from one domain to another—viewing time from different perspectives within a media composition system.

In this chapter, we will first explore the foundational concepts of temporal projections and their mathematical properties. We will then examine how these projections can be embedded within topologies, enabling complex temporal transformations. Finally, we will demonstrate these concepts through practical examples of increasing complexity, showing how multiple projections can be composed to create sophisticated temporal effects.

## Applications of Temporal Projection

Temporal projection has numerous applications in media composition systems:

1. **Variable Speed Effects**: Projecting a linear time domain through a non-linear mapping function to create speed ramps and other time-warping effects.

2. **Frame Rate Conversion**: Projecting media from one frame rate to another through a sampling function topology.

3. **Interactive Media**: Dynamically adjusting temporal relationships based on user input by projecting through a topology that responds to interaction.

4. **Temporal Synchronization**: Aligning multiple media elements with different internal timelines through projection into a common presentation timeline.

In each of these applications, the mathematical properties of temporal projections ensure that the operations are well-defined and can be precisely controlled.

## Foundations of Temporal Projections

Temporal projections involve mapping time from one domain or representation to another, often through multiple transformations. In the context of the temporal algebra, a projection is a mathematical operation that transforms temporal coordinates from one space to another. Figure 24 visualizes how time can be mapped from one domain to another through a projection operation.

![Figure 24](assets/17469131894461.jpg)
***Figure 24**: A temporal projection mapping time from presentation space to media space.*

A critical property of these projections is that they are both invertible and differentiable. This means we can not only map forward from one temporal domain to another but also precisely reverse the mapping. The differentiability ensures that the rate of change is well-defined at every point, which is essential for operations like speed ramping or variable time warping.

Formally, a function f: X → Y is invertible if for every y in Y that is in the range of f, there exists exactly one x in X such that f(x) = y. The differentiability property ensures that the derivative f'(x) exists at every point in the domain, allowing us to determine the instantaneous rate of change of the temporal mapping.

While ideal mappings would be bijective (one input value maps to exactly one output value), in practice we often encounter injective mappings (one input value may map to multiple output values), such as when time "doubles back" in a rewind effect. When this occurs, we maintain effective bijectivity by subdividing the mapping into multiple bijective segments. Figure 25 demonstrates this point.

![Figure 25](assets/17469132284417.jpg)
***Figure 25**: Invertible and differentiable properties of temporal projection, require two bijective mappings for the two solutions.*

## Embedding Time Mappings in a Topology

Given a temporal topology consisting of media intervals (as discussed in Chapter 4), we assign a mapping function to each interval. These mapping functions transform time from one domain to another within their respective intervals.

To reason about these mapping functions collectively, we embed them within the topology itself. The topology orders these mapping curves in the same way that clips are ordered in the composition. Each clip corresponds to a mapping curve, where the curve represents a function that maps input time to output time. Figure 26 shows how these functions are embedded within the overall topology.

![Figure 26](assets/17469133168518.jpg)
***Figure 26**: Mapping curves embedded within a temporal topology, where each curve transforms time from one domain to another.*

### Properties of the Temporal Mapping Domain

Recall that a topology in this framework represents a mapped domain of right-met, piecewise continuous functions that transform input time to per-interval output times. These continuous functions have key mathematical properties:

1. Each function is individually invertible
2. Each function is differentiable
3. Consequently, the entire domain is invertible, while differentiability is guaranteed within each segment, with potential discontinuities at the segment boundaries

These discontinuities at segment boundaries are precisely identified during the subdivision process, allowing us to manage them explicitly. Figure 27 illustrates these properties.

![Figure 27](assets/17469134433070.jpg)
***Figure 27**: Piecewise continuous functions forming a complete temporal mapping domain with invertible and differentiable properties within each segment.*

## Measuring Time Across Discontinuous Intervals

One of the primary motivations for embedding temporal intervals in a topology is to enable measurement between discontinuous time points. Within a single interval, the distance between two points can be directly measured using metric space properties. However, between points on discontinuous intervals, direct measurement is not possible.

A topology provides the framework to measure between points on different discontinuous intervals through a non-metric space approach. This capability is essential for complex editorial operations that need to relate temporally disconnected elements (Figure 28).

![Figure 28](assets/17469135394791.jpg)
***Figure 28**: Measurement between points on discontinuous temporal intervals is possible via topological relationships.*

### Boundary Constraints in Projection

A topology has explicit bounds, which are defined by the bounds of its constituent intervals. When projecting one topology through another, we treat the bounds of the intervals as boundary constraints. These constraints ensure that the projection respects the temporal limits of each interval.

Formally, when projecting topology A through topology B, the domain of the resulting topology is the intersection of the domain of A and the inverse image of the domain of B under the mapping function. This ensures that we only operate within valid regions of both topologies.

## The Unit Identity Interval

The simplest possible topology is a continuous unit identity time interval. This topology consists of a single segment with a linear curve of slope 1. This fundamental topology serves as a reference point for understanding more complex temporal projections (Figure 29).

![Figure 29](assets/17469135585660.jpg)
***Figure 29**: The unit identity interval as the simplest possible topology, consisting of a single segment with a linear curve of slope 1.*

## The Nature of Topological Projection

Projection is the operation of transforming something from one space to another. In the context of the temporal algebra, the specific type of projection we're concerned with is the projection of one topology through another.

Given the definition of a point as a half-space interval, and the existence of the unit interval, we can narrowly define projection: one topology projected through another topology yields a new topology.

This operation is fundamental to understanding how time transforms across the various domains in the media composition model. When we project a temporal structure from one domain (e.g., composition time) to another (e.g., presentation time), we are performing a topology projection. This builds directly upon the coordinate system transformations discussed in Chapter 3, extending them to handle complex, piecewise temporal structures.

### An Example

![Figure 30](assets/17469181822698.jpg)
***Figure 30**: Example timeline with nested speed modifications - an 80% slowdown containing a clip with a further 60% slowdown.*

The timeline interval in Figure 30 embeds some clips and slows them to 80% of their natural rate. The highlighted clip within it has a further slowdown of 60%.

First, we construct a topology to represent the scenario (Figure 31).

![Figure 31](assets/17469182915281.jpg)
***Figure 31**: Construction of topologies A and B representing the timeline and clip transformations respectively.*

We will project topology B through topology A:

a represents a speed up on a media clip. (clip->media)
b represents mapping the clip on a timeline (track->clip)

We join the clip axes with a change of basis if necessary. Figure 32 illustrates this multi-step projection.

![Figure 32](assets/17469184814083.jpg)
***Figure 32**: The projection process showing how a point on the track's timeline (left) maps to clip space, and then to media space (right).*

By tracing from a point on the track's timeline, through the "b" projection operator to the clip space, and from the clip space through the "a" projection operator, we determine the index into the media clip that corresponds.

We can join the axes, and show that we can reduce the operation to a single operation in a higher dimensional space, which means these operations may be analytically reducible to a single step. As Figure 33 demonstrates, this allows us to analytically reduce complex transformations.

![Figure 33](assets/17469187749517.jpg)
***Figure 33**: Joined axes visualization showing how multiple transformations can be reduced to a single operation in a higher dimensional space.*

Projections with non-linearities work the same way. Figure 34 shows how the same approach works with non-linear transformations.

![Figure 34](assets/17469188888090.jpg)
***Figure 34**: Non-linear projection example showing how non-linear transformations follow the same projection principles.*

In this case, the functional reduction results in a simple scaling operation that can be computed in one step. Figure 35 illustrates how this complex series of operations reduces to a straightforward calculation.

![Figure 35](assets/17469189548959.jpg)
***Figure 35** Reduction of complex projections to a simple scaling operation, demonstrating the power of the compositional approach.*

## Boundary Constraints

Topological projections are valid within the intersection of the bounds of the intervals. Figure 36 shows how these constraints define the valid projection space.

![Figure 36](assets/17469190406862.jpg)
***Figure 36**: The boundary constraints of example topologies a and b.*

As illustrated in Figure 37, when we join intervals a and b via their shared axis, the projection is continuous and available only within the shaded regions defined by their bounds.

![Figure 37](assets/17469190931735.jpg)
***Figure 37**: Joined intervals a and b showing the continuous projection region (shaded) defined by their intersection.*

## Advanced Projections and Complex Topologies

Now that all the fundamental operations are demonstrated, let's explore the projection of more complex topologies. Figure 38 illustrates two topologies with more sophisticated temporal characteristics than the previous examples.

![Figure 38](assets/17469893683296.jpg)
***Figure 38:** Topology a involves three segments (slow, hold, and rewind), while topology b shows an ease curve (deceleration followed by acceleration).*

Topology a is composed of three segments where time proceeds slowly, holds on a frame, and then rewinds. Topology b shows an ease that decelerates to a target frame, and then accelerates nearly back to the beginning. Both topologies are injective, in that particular points on the projective axes map to more than one point on the timeline.

To handle these more complex mappings, we align the change of basis axes, and then mutually project end points and critical points to create a new set of subdivided topologies, as illustrated in Figure 39. This step converts the injective mappings to a set of bijective mappings.

![Figure 39](assets/17469897699960.jpg)
***Figure 39:** After joining the mutual axis, the end points of topology a are used to subdivide topology b. The end points and critical points of topology b then subdivide topology a.*

Each of the new mappings is differentiable, invertible, and affinely composable, as we've previously explored. This subdivision process is key to handling complex temporal transformations while maintaining the mathematical properties we require.

## Non-Analytical Compositions through Approximation

The method described can be extended to functions that cannot be analytically composed, through the use of Jacobians and linear approximation. This preserves the desirable properties of differentiability, invertibility, and affine composition even for complex, non-analytical functions.

Figure 40 shows two analytic functions with Jacobians placed according to an approximation error analysis. The Jacobian matrix, which contains all first-order partial derivatives of a vector-valued function, allows us to linearly approximate how small changes in the input affect the output near specific points.

![Figure 40](assets/17469902643031.jpg)
***Figure 40**: Topologies a and b with Jacobians placed according to an error minimization process.*

The location of these Jacobians guides the mutual subdivision process as before, as shown in Figure 41. By placing subdivision points where the error of linear approximation would exceed a threshold, we can maintain accuracy while keeping the number of segments manageable.

![Figure 41](assets/17469904234700.jpg)
***Figure 41**: The Jacobians guide the subdivision process, ensuring accurate approximation of the composed function.*

## Practical Application: Composing Complex Functions

To demonstrate the practical power of the approach, Figure 42 shows an example where a sigmoid function is projected through a parabola to generate a bell-shaped curve. This illustrates how complex, non-linear temporal effects can be created through the composition of simpler functions.

![Figure 42](assets/17469905525263.jpg)
***Figure 42**: Projecting a sigmoid function through a parabola to generate a bell-shaped curve, demonstrating the creation of complex temporal effects through composition.*

Non-linear editing tools offer many forms of analytic mapping functions that do not practically compose through direct algebraic methods. For example, a Bézier time curve is cubic, and the projection of one such curve through another yields a function of ninth order (3²=9); a subsequent projection of the result would reach order 27 (3³). This exponential growth in complexity makes direct algebraic composition computationally impractical.

Fortunately, Pythagorean Hodographs—special polynomial curves whose derivatives have the Pythagorean property—provide the critical information we need to guide the subdivision process. By identifying optimal subdivision points based on the geometric properties of these curves, even these challenging projections can be handled efficiently using this approach.

This type of projection has practical applications in media composition, such as creating sophisticated ease-in/ease-out effects or timing variations for animation. By composing mathematically well-defined functions, artists can achieve precise control over temporal transformations without requiring deep mathematical expertise in the underlying complexity.

## Summary

Projection through a topology provides a powerful mathematical framework for understanding and manipulating time across various domains in media composition systems. The full algorithm for projecting topology B through topology A can be summarized as:

1. **Align Coordinate Systems**: Perform a change of basis transformation to align the shared axis between topologies A and B

2. **Identify Critical Points**: Determine all critical points from both topologies, including:
   - Endpoints of intervals
   - Points of non-differentiability
   - Extrema and inflection points of non-linear mappings

3. **Create Bijective Subdivisions**: Mutually subdivide both topologies at these critical points to create a set of bijective mapping segments

4. **Compose Transformations**: For each corresponding segment pair, compose their mapping functions (either analytically when possible or through approximation methods like Jacobians)

5. **Apply Boundary Constraints**: Ensure the projection is only valid within the intersection of the bounds of both topologies

6. **Transform Result**: Map the resulting composite topology back to the target coordinate system

This approach ensures that complex temporal transformations maintain the critical properties we require:

- Invertibility: We can map in both directions between domains
- Differentiability: The rate of change is well-defined at every point
- Composability: Multiple transformations can be reduced to simpler operations

For cases where analytical composition is not possible, we can use piecewise linear approximations guided by Jacobians, with the density of subdivision points determined by error minimization.

The projection framework developed in this chapter builds directly upon the coordinate systems presented in Chapter 3 and the topology structures from Chapter 4, providing a comprehensive approach to temporal transformation. In the next chapter, we will explore how these continuous projections interact with the discrete nature of media samples through sampling theory, addressing the critical challenge of converting between continuous time domains and the discrete samples required for digital media.

# Chapter 6: Sampling Theory

## In Which, The Rubber Hits The Road

The preceding chapters have established a mathematical framework for time as a continuous dimension in media composition systems. We have developed coordinate systems, transformations, and topological representations that allow us to reason rigorously about temporal relationships. However, a critical gap remains: bridging the continuous nature of time with the fundamentally discrete nature of digital media.

This chapter explores sampling theory as the essential connective tissue between the abstract temporal algebra and the practical reality of digital media. We will examine how discrete media samples relate to continuous time domains, and how we can leverage frequency domain techniques to manipulate these relationships with mathematical precision.

## The Continuous-Discrete Duality

### The Fundamental Challenge

Media composition operates within a striking duality: time itself is continuous, but media exists as discrete samples. This duality creates a fundamental tension at the heart of media systems.

Consider the video clip in Figure 43; it has a frame rate of 24 frames per second. In the continuous time domain, we have a smooth flow of time. However, the media itself consists of 24 discrete samples per second, each representing a snapshot of a continuous reality. The relationship between these two representations—continuous and discrete—is the province of sampling theory.

![Figure 43](assets/17470308117865.jpg)
***Figure 43**: The parent temporal space is continous, but the media clip contains snapshots of continuous reality.*

## Sampling Functions in Time Algebra

### Definition of a Sampling

We define a "Sampling" as a mapping from discrete samples to continuous intervals. Since intervals are topologies (as established in Chapter 4), and we can build a topology of adjacent topologies, we can apply the projection mathematics to manipulate samplings as well.

A sampling function S maps a set of discrete sample indices `I = {i₀, i₁, ...}` to a set of continuous intervals `T = {t₀, t₁, ...}` in a given temporal domain; we can represent a sampling function S as:

`S: I → T`

`I` may be a set of frame indices, and `T` may be the interval they are visible on a timeline. For regular sampling, such as constant frame rate video, the mapping is straightforward:

`S(i) = [i/r, (i+1)/r)`

Where `r` is the frame rate, and the interval is right-open (inclusive on the left, exclusive on the right) as established in the interval conventions from Chapter 3.

### Frequency Domain Perspective

From a frequency domain perspective, we can view the sampling process as a phase modulus that implies a topology of regular intervals. Every time the phase wraps, the sample index (e.g., "frame") increments (Figure 44). This frequency domain representation provides powerful tools for manipulating samplings without explicitly constructing a complete topology.

![Figure 44](assets/17470308962642.jpg)
***Figure 44**: The phase modulus corresponds to shutter intervals.*

The sampling rate establishes a base frequency, while phase offsets determine the precise alignment of samples within the continuous domain. This approach allows us to leverage the established mathematics of signal processing to work with the temporal algebra.

## Manipulating Samplings Through Projection

### Transforming the Mapping, Not the Content

Manipulating a sampling through projection doesn't change the samples themselves, but rather transforms the mapping to the parent temporal scope.

For example, if a scope for a sampling is sped up by a factor of 2, as in Figure 45, then the interval in the presentation space for each sample is half as long as it was before. The samples themselves remain unchanged, but their relationship to the parent temporal domain is transformed.

![Figure 45](assets/17470311139438.jpg)
***Figure 45**: Generating in betweens by doubling frequency.*
This distinction allows us to separate two fundamentally different operations:

1. **Remapping samples**: Transforming the relationship between existing samples and continuous time
2. **Generating new samples**: Creating new sample content through fetching or resampling

### Remapping Example: Time Stretching

Consider a request to "slow this clip down by 50%." There are two fundamentally different approaches to this operation:

#### Approach 1: Hold Every Frame Twice (Sample Remapping)

![Figure 46](assets/17470309924980.jpg)
***Figure 46**: Holding every frame twice by warping time by a factor of two.*

In this approach, show in Figure 46, we operate on the ordering of existing samples, effectively holding each frame for twice as long:

```
Original mapping: 0→0, 1→1, 2→2, 3→3, 4→4, ...
New mapping:      0→0, 1→0, 2→1, 3→1, 4→2, ...
```

We can model this as:
- Frequency × 0.5 (half the original frequency)
- Time × 2 (double duration)
- Phase offset = 0 (align with original sample boundaries)

This approach reuses existing samples without creating new content.

#### Approach 2: Generate New Frames (Sample Generation)

![Figure 47](assets/17470312119030.jpg)
***Figure 47**: Generating in betweens on held twos by doubling the frequency and time.*

Alternatively, we could modify continuous time in the animation and render twice as many frames, as show in Figure 47:

```
Original mapping: 0→0, 1→1, 2→2, 3→3, 4→4, ...
New mapping:      0→0, 1→0.5, 2→1, 3→1.5, 4→2, ...
```

We can model this as:
- Frequency × 1 (same frequency)
- Time × 2 (double duration)
- Phase offset = 0 (align with original sample boundaries)

This approach requires generating new sample content through interpolation or recomputation.

### The Role of Phase in Sampling

Phase offsets provide precise control over which samples align with the parent temporal scope. For example:

- In the "hold every frame twice" example, a phase offset of 0 means we align with even frames
- A phase offset of 1 would align with odd frames
- We can model arbitrary holds by using a frequency of 1/n to hold for n frames, with phase offset governing which frames are picked

Figure 48 illustrates a hold on evens, and a hold on odds, using a phase offset to accomplish it.

![Figure 48](assets/17470314196745.jpg)
***Figure 48**: Using phase offset to accomplish a hold on evens, and a hold on odds.*

This phase-based approach allows for complex and precise control over temporal relationships. Figure 49 shows a serious of aribtrary holds.

![Figure 49](assets/17470315018465.jpg)
***Figure 49**: A series of arbitrary held frames.*


## Frame Kernels and Reconstruction

### The Frame Kernel Concept

When a non-linear editor displays a timeline, it might show time as a hairline (a point), but in reality, that point corresponds to the duration of a frame. This relationship can be understood through the concept of a frame kernel (Figure 50).

![Figure 50](assets/17470316928929.jpg)
***Figure 50**: When a tool shows a hairline to indicate time, it implicitly indicates an interval.*

A frame kernel, when convolved with the interval of contribution, produces the frame interval. Everything up to the end of the current frame contributes in some way to the sample representing that frame (Figure 51).

![Figure 51](assets/17470317560200.jpg)
***Figure 51**: The frame kernel is convolved with the frame interval, and any preceding support.*


The position and shape of the frame kernel describes what we might call "house style"—whether the sampling biases to the beginning, middle, or end of the frame, or even outside the frame (Figure 52).

![Figure 52](assets/17470318212048.jpg)
***Figure 52**: The position of the frame kernel may be adjusted to reflect house style, or technical considerations.*

Different output domains may have different house styles for the same composition. For example, when does a sound effect happen in relation to a visual cue? Does it align with the start of the image frame, the middle, or the end?

### Reconstruction of Continuous Signals

To generate output frames, we must use sampling theory to reconstruct continuous signals from discrete samples. This process involves:

1. Defining appropriate sampling kernels for the domain
2. Applying reconstruction functions to generate a continuous representation
3. Resampling this continuous representation at the output rate

The quality of this reconstruction depends on the mathematical properties of the kernels and reconstruction functions used.

## Resampling Techniques

When new samples must be generated, two primary approaches are available:

### 1. Fetching New Samples

New samples can be obtained by:
- Generating via physics simulation (recomputing the underlying model)
- Drawing new pictures (re-rendering at the new sampling rate)
- Accessing source media at different sample positions

This approach provides the highest quality but may be computationally expensive or impossible in some contexts.

### 2. Resampling with Convolution

Alternatively, new samples can be derived from existing ones through:
- Hat filter for audio samples (simple interpolation)
- Lanczos filter for image frames (high-quality interpolation)
- Other convolution kernels optimized for specific media types

The selection of an appropriate convolution kernel depends on the media type, computational constraints, and quality requirements.

## Continuous Parametric Sampling

When we consider sampling as a bridge between continuous and discrete domains, we typically think in terms of regular temporal sampling. However, to fully appreciate the power of sampling in media systems, we must consider alternative parametric spaces that can provide unique advantages for certain operations. This section explores the relationship between continuous parametric spaces and the temporal algebra.

### Parametric Spaces and Worldlines

Let us consider a simple physical scenario: a ball falling toward a ground plane under gravity in an otherwise empty universe (Figure 53). This seemingly simple scenario reveals profound insights about the relationship between sampling and continuity.

![Figure 53](assets/17470321777428.jpg)
***Figure 53**: A ball falling towards the ground under the influence of gravity in an otherwise empty universe.*

The ball's path through space-time—its worldline—is continuous, but there's a critical event that divides this continuity: the collision with the ground. From the perspective of energy, pre-collision and post-collision represent two entirely different manifolds. Before collision, energy has not been exchanged with the ground; after, it has (Figure 54). These are fundamentally separate domains despite the apparent continuity of physical space.

![Figure 54](assets/17470322408128.jpg)
***Figure 54**: Pre-collision and post-collision manifolds.*

This division illustrates a key insight: we can represent continuous phenomena through multiple parametric spaces connected by transformation functions.

### Uniform Parametrization and Sampling Strategies

Consider the ball's worldline before the collision. We can imagine a warped parametric space with uniform parametrization for this portion of the path (Figure 55).

![Figure 55](assets/17470323143968.jpg)
***Figure 55**: A uniform parameterization of the ball's wordline.*

Within this continuum, we have several sampling options:

1. **Uniform temporal sampling**: We can sample the ball's position at regular intervals of time.
2. **Uniform parametric sampling**: Alternatively, we can sample uniformly in the parametric space, which might correspond to equal arc lengths along the curve of motion.
3. **Event-based sampling**: We could sample based on significant events or changes in the system.

Each approach produces different discrete representations of the same continuous phenomenon, with different advantages for particular applications.

### Bridging Parametric and Temporal Spaces

The temporal component acts as a bridge between parametric space and temporal topologies. By projecting sampling functions through this bridge, we gain the ability to work with non-uniform sampling patterns that nevertheless maintain critical mathematical properties.

Consider the ground plane in this example (Figure 56):
- In position space, it's a fixed horizontal line
- In parametric space, it may appear as a curved surface
- The collision time becomes a function of the parametric space

![Figure 56](assets/17470323956587.jpg)
***Figure 56**: The ground play in positional space, and parametric space.*

This relationship enables us to parameterize the frame kernel—the fundamental unit of sampling in this system—based on meaningful events rather than arbitrary temporal divisions (Figure 57).

![Figure 57](assets/17470324738485.jpg)
***Figure 57**: The frame kernel in parametric space.*

Typically, the point of collision is calculated in positional space through Newtonian search through time subdivision. In an appropriately chosen parametric space, time could be computed directly from the location of the ground plane in that space.

### Example: Continuous Collision Detection

The traditional approach to physics simulation involves discrete time stepping, which can lead to problems when objects move quickly relative to the time step size; if the ball is moving rapidly, it might be above the ground in one time step and beneath it in the next, "tunneling" through the collision surface as shown in Figure 57a.

![Figure 57a](assets/17477629523393.jpg)

***Figure 57a**: Tunneling occurs when discrete time steps miss the exact moment of collision.*

Rather than relying solely on discrete sampling, continuous collision detection (CCD) addresses this problem by solving for the precise time of collision within the bracketing interval. Mathematically, we first identify that a collision may have occurred when we detect one of two conditions:

- The ball has penetrated the ground plane between time steps
- The ball has passed through the ground plane entirely between time steps

This gives us a bracketing interval `[t₀, t₁)` where:

At time `t₀`, the ball is above the ground (no collision)
At time `t₁`, the ball has penetrated or passed through the ground (post-collision)

The exact collision time `t_c` (`Bc` in the earlier discussion) must lie within this indeterminate interval.

#### Parametric Equation of Motion

For simple motions like constant acceleration, this inverse can be calculated analytically. For more complex motions, numerical methods such as Newton-Raphson iteration can be employed. The ball's motion is simple, so to find the exact collision time, we express the ball's position as a parametric function of time. For a ball falling under constant gravitational acceleration, this is given by:

`y(t) = y₀ + v₀t + ½at²`

Where:

`y(t)` is the height of the ball at time `t`
`y₀` is the initial height at time `t₀`
`v₀` is the initial velocity at time `t₀`
`a` is the acceleration due to gravity (e.g. -9.8 m/s²)

If we define the ground plane to be at y = 0, then the collision occurs when `y(t_c) = 0`. Rearranging gives:

`y₀ + v₀t_c + ½at_c² = 0`

This is a quadratic equation in `t_c`, which we can solve using the quadratic formula:

`t_c = (-v₀ ± √(v₀² - 2ay₀))/a`

Since we're looking for the time when the ball first contacts the ground, we take the smaller positive root that lies within our bracketing interval `[t₀, t₁)`.

#### Parametric Continuity Across the Collision

Now that the exact collision time `t_c` has been identified, we  split the original interval `[t₀, t₁)` into two sub-intervals:

- The pre-collision interval `[t₀, t_c)`
- The post-collision interval `[t_c, t₁)`

Each of these intervals has its own parametric equation of motion, with continuity of position at `t_c` but a discontinuity in velocity (due to the collision impulse).

The position continuity constraint ensures:

`y_pre(t_c) = y_post(t_c) = 0` (at the ground plane)

While the velocity undergoes a discontinuous change:

`v_post(t_c) = Transform(v_pre(t_c))`

This approach maintains the physical validity of the simulation and leverages the topological aspects of the temporal framework.

#### Topological Representation

Physical reality naturally conforms to the topological structures we've defined mathematically in this framework, representing temporal structures as piecewise continuous functions with well-defined boundaries.

The collision event creates a natural boundary in the temporal topology. As discussed in Chapter 4, the collision point `t_c` serves as a critical node in the topology, dividing our timeline into distinct pre-collision and post-collision segments. Each segment maintains its own coherent physical laws while the collision itself represents a discontinuity in the topology.

#### Connection to Sampling Theory

With the precise collision time determined, a sampling strategy can now properly account for the discontinuity in the system's behavior. For a frame sampler evaluating at time `t_sample`, we first determine which segment of our topology contains `t_sample`, then apply the appropriate parametric equation for the segment. This ensures that rendered images accurately depict the collision, even if the rendering sample rate is completely independent from the simulation time steps.

### Implications for Interactive Systems

While this example focused on deterministic physics, by framing continuous collision detection within our temporal algebra, we build a bridge between the deterministic world of classical physics simulation and the indeterminate nature of interactive systems. This will be explored more deeply in subsequent chapters.

### Implications for Media Systems

This perspective offers several powerful capabilities for media composition:

1. **Adaptive sampling**: We can adjust sampling density based on the complexity or importance of different segments of media.

2. **Event-centered sampling**: Critical events in media (cuts, transitions, key frames) can anchor the sampling strategy rather than being awkwardly aligned to fixed sampling intervals.

3. **Continuous interpolation**: By maintaining a continuous parametric representation, we can generate samples at arbitrary positions with mathematically sound interpolation.

4. **Physical simulation mapping**: For applications involving simulated physics (animation, virtual reality), we can map sampling strategies to the underlying physical parametric spaces.

5. **Scale-invariant operations**: Operations defined in parametric space remain valid regardless of the temporal sampling rate of the media.

In the context of the temporal algebra, parametric sampling introduces a layer of indirection between the topological representations and the final discrete samples. This indirection provides flexibility while maintaining mathematical rigor. The ability to project from simulation time to rendering time with this level of precision demonstrates how the framework bridges the gap between theoretical mathematics and practical implementation challenges in media systems. It also validates the framework's utility across diverse domains, from traditional media composition to interactive physics simulation.

### Connecting to Topological Projection

Parametric sampling naturally connects to the concept of topological projection discussed in Chapter 5. A parametric space with its sampling function can be viewed as a specialized kind of topology. When we project one topology through another, we are effectively creating a new sampling space.

The collision example illustrates this principle clearly: the collision event creates a boundary constraint in the projection, dividing the parametric space into pre-collision and post-collision domains. By projecting through this boundary, we maintain mathematical continuity while respecting the physical discontinuity in the system.

## Practical Example: Retiming a Mixed Media Composition

Consider a composition with synchronized picture and audio tracks that must be retimed. The process involves:

1. The parent metric space relates the picture continuum to the audio continuum
2. To render the corresponding data from the retimed track, we create frame sampling kernels for all frames whose start point falls within the interval of interest
3. For each sampling kernel, we compute the contribution of source samples through convolution
4. The resulting output frames maintain temporal relationships established by the temporal algebra

Since samples are intervals, they can be represented by topologies, allowing the projection mathematics to apply seamlessly.

## The Sampling Topology

### Continuous Representation of Discrete Samples

Every sampling defines a topology—a set of intervals that partition the continuous timeline. This topology has specific properties:

1. It is a right-met sequence of intervals
2. For regular sampling, the intervals have equal duration
3. For variable rate sampling, the intervals have varying durations

This topological view allows us to apply the full power of the temporal algebra to discrete sampling problems.

### Transformations on Sampling Topologies

Applying a projection to a sampling topology transforms the intervals in a well-defined way. For example:

- A linear speed change (e.g., 2×) uniformly scales all intervals
- A non-linear speed change (e.g., ramp from 1× to 2×) applies a non-uniform scaling to intervals
- A reverse operation inverts the order of intervals

These transformations maintain the topological properties established in Chapter 4, ensuring mathematical consistency throughout this framework.

## Interpolation as Continuous Mapping

### Continuous Representation Through Interpolation

When we interpolate between samples, we are effectively constructing a continuous representation from discrete data. In the context of the temporal algebra, interpolation can be viewed as a mapping:

`I: [0, 1) → V`

Where V is the value space of the media (e.g., pixel colors, audio amplitudes).

This mapping creates a continuous function that can be sampled at arbitrary points, allowing for precise temporal manipulations.

### Interpolation Methods in Temporal Context

Different interpolation methods provide different continuous representations:

1. **Nearest Neighbor**: The simplest approach, creating a step function
   - Mathematically: `I(t) = V(floor(t))`
   - Appropriate for hold frames or when transitions must be discrete

2. **Linear Interpolation**: A first-order approximation creating straight lines between samples
   - Mathematically: `I(t) = V(floor(t)) * (1-f) + V(ceil(t)) * f`, where `f = t - floor(t)`
   - Suitable for simple transitions but introduces trajectory errors

3. **Cubic Interpolation**: A third-order polynomial providing smooth transitions
   - Mathematically: `I(t) = a * V(floor(t)-1) + b * V(floor(t)) + c * V(ceil(t)) + d * V(ceil(t)+1)`
   - Where `a`, `b`, `c`, and `d` are cubic coefficients based on `t`
   - Provides smoother motion with better preservation of trajectory

4. **Sinc Interpolation**: The theoretically optimal interpolation for bandlimited signals
   - Mathematically: `I(t) = sum(V(i) * sinc(t - i))` for all samples `i`
   - Provides the best quality but is computationally expensive

The choice of interpolation method affects not only the visual or auditory quality but also the temporal characteristics of the resulting media.

## Temporal Aliasing and Nyquist Limits

### The Nyquist-Shannon Sampling Theorem

A fundamental result in sampling theory is the Nyquist-Shannon sampling theorem, which states that to perfectly reconstruct a continuous signal, the sampling rate must be at least twice the highest frequency present in the signal.

In the context of temporal media, this has important implications:

1. Temporal details that occur faster than half the frame rate cannot be accurately represented
2. Attempting to represent such details leads to temporal aliasing—artifacts that misrepresent the original signal

### Dealing with Temporal Aliasing

To address temporal aliasing in this framework:

1. **Pre-filtering**: Before sampling, the continuous signal can be filtered to remove frequencies above the Nyquist limit
2. **Motion blur**: In visual media, motion blur effectively integrates over time, serving as a natural anti-aliasing filter
3. **Adaptive sampling**: Variable rate sampling can be used to increase the sampling rate during rapid changes

These techniques help maintain temporal fidelity while working within the constraints of discrete sampling.

## The Sampling Function Taxonomy

### Types of Sampling Functions

This framework categorizes sampling functions into several types:

1. **Regular Sampling**: Constant intervals between samples
   - Example: Standard frame rates like 24fps, 30fps, 60fps

2. **Variable Rate Sampling**: Intervals that vary according to a function
   - Example: High-frame-rate capture of fast motion, standard rate for slower motion

3. **Adaptive Sampling**: Sampling rate adjusted based on content complexity
   - Example: More samples during complex motion, fewer during static scenes

4. **Stochastic Sampling**: Samples distributed according to a probability distribution
   - Example: Monte Carlo rendering techniques for complex lighting

Each type of sampling function has different mathematical properties and different implications for temporal operations.

### Sampling Function Composition

Sampling functions can be composed, creating complex relationships between different temporal domains. For example:

- A camera captures at 120fps (regular sampling)
- The footage is converted to 24fps (regular resampling)
- A speed ramp is applied (variable rate resampling)
- The result is displayed at 60fps (regular resampling)

The algebraic framework allows each of these transformations to be precisely defined and composed to determine the final temporal relationships.

### Coordinate Systems and Sampling

Chapter 3 established the concept of time as a normed vector space with affine transformations between coordinate systems. Sampling functions extend this framework by defining how discrete indices map to this continuous space.

The affine transformations can be applied to both the continuous domain and the sampling functions themselves, providing a unified mathematical treatment.

### Topology and Sampling

Chapter 4 introduced the topological representation of temporal structures. Sampling creates a specific type of topology—a partitioning of the timeline into intervals associated with discrete samples. The operations defined on topologies can be applied to sampling topologies, allowing for complex temporal manipulations.

### Projection and Sampling

Chapter 5 explored projection through temporal topologies. Sampling functions can be viewed as a special case of projection, mapping from a discrete domain to a continuous one.

The composition of projections described in Chapter 5 applies equally to sampling functions, allowing for complex chains of temporal transformations that maintain mathematical rigor throughout.

## Practical Example: SMPTE Timecode Drop Codes

SMPTE timecode (Society of Motion Picture and Television Engineers) represents one of the most widely used standards in media production, yet it embodies a fundamental contradiction in how time is represented. While formatted to display `hours:minutes:seconds:frames (HH:MM:SS:FF)`, suggesting a measurement of elapsed time, SMPTE timecode is fundamentally a sequential labeling system for frames rather than a true temporal metric. Consider a timecode reading of `01:00:00:00` (1 hour, 0 minutes, 0 seconds, 0 frames):

- In a 24fps project, this represents the 86,400th frame (24 × 60 × 60)
- In a 30fps project, this represents the 108,000th frame (30 × 60 × 60)
- In a 29.97fps drop-frame project, the actual elapsed time is slightly more than one hour due to frame numbering adjustments

These equivalent timecode readings represent different absolute temporal positions depending on the frame rate of the project. This frame-counting approach, while practical for traditional editing workflows, creates challenges when media of different frame rates must be integrated or when precise temporal relationships must be maintained.

The complications of SMPTE timecode are compounded by drop-frame timecode, developed to reconcile the NTSC color television frame rate of 29.97fps with timecode's assumption of 30fps:

- Drop-frame timecode skips two frame numbers (not actual frames) at the start of each minute except every tenth minute
- This adjustment compensates for the 0.1% slower rate of 29.97fps compared to 30fps
- After one hour, non-drop frame NTSC timecode is approximately 3.6 seconds behind real time

This compensatory mechanism illustrates the awkward retrofitting required when frame-based labeling systems attempt to align with absolute time.

### SMPTE Timecode and Sampling Theory

SMPTE timecode can be understood as a specialized form of temporal sampling function. Recalling the definition, a sampling function `S` maps a set of discrete sample indices `I` to a set of continuous intervals `T` in a given temporal domain:

`S: I → T`

In the case of SMPTE timecode, the sample indices `I` are the frame labels `(HH:MM:SS:FF)`, and the continuous intervals `T` are the actual time spans that each frame represents.

For non-drop frame timecode at frame rate `r`, the sampling function, mapping each frame to a right open interval in continuous time, is straightforward:

```
S(HH:MM:SS:FF) = [HH*3600 + MM*60 + SS + FF/r, HH*3600 + MM*60 + SS + (FF+1)/r)
```

For drop-frame timecode, the sampling function becomes more complex due to the skipped frame numbers. Nonetheless, a sampling function injectively mapping from non-uniformly incrementing SMPTE drop code labels to continous time intervals may be defined, creating a topology where the intervals at minute boundaries (except for every tenth minute) are effectively "compressed" by the skipped frame numbers. By treating the timecode as a sampling of a continuous function, we can interpolate between frames to derive continuous time values.

### Resolving Multi-Rate Compositions

When media elements with different frame rates must be composed together, the traditional approach is to resort to conforming everything to a common rate. Using the projection framework, we can instead maintain each element in its native rate and define explicit projections between their different temporal domains, preserving the full temporal fidelity of each element while ensuring accurate synchronization.

## Summary

Sampling theory bridges the gap between the continuous nature of time and the discrete reality of digital media. By integrating sampling into the temporal algebra, we create a comprehensive framework that maintains mathematical rigor while addressing the practical challenges of media composition.

The key insights from this chapter include:

1. Samplings map discrete indices to continuous intervals, creating a topology that can be manipulated using the framework's existing mathematical tools

2. Manipulating a sampling through projection transforms the mapping to the parent temporal scope without changing the samples themselves

3. Generating new samples requires either fetching from the source or resampling using convolution techniques

4. Frame kernels define the relationship between points in time and the duration of media samples

5. Interpolation creates continuous representations from discrete samples, enabling precise temporal manipulations

6. The Nyquist-Shannon theorem establishes fundamental limits on temporal representation, introducing considerations of temporal aliasing

In the next chapter, we will explore how this framework extends to the domain of interactive media, where timelines become dynamic and responsive to user input.

# Chapter 7: Interactive Timelines

## Indeterminancy, Observability, Many Worlds

In previous chapters, we established a foundation for representing and manipulating time in media composition systems. We explored the mathematical properties of time as a normed vector space, the topological structures for representing temporal relationships, and the projection of time through these topologies. We also examined the intersection of continuous and discrete time through sampling theory, introducing the concept of parametric sampling spaces.

This chapter extends these concepts to address one of the most challenging aspects of temporal media: indeterminancy. Interactive media, real-time systems, and dynamic content all share a fundamental characteristic—their timelines are not fixed but contingent on events that cannot be predetermined. Understanding how to model and work with such indeterminate temporal structures is essential for next-generation media systems.

## The Nature of Indeterminancy

### The Messy Middle

The real world, as opposed to idealized mathematical models, is fundamentally "squishy." Let's return to the ball and ground plane example, Figure 57.

![Figure 57](assets/17474451170455.jpg)
***Figure 57**: Revisiting the ball bouncing on the plane.*


In the initial model, we represented the ball's collision with the ground as an instantaneous event that cleanly divided two temporal manifolds: pre-collision and post-collision. However, reality is more complex (Figure 58). The exchange of energy between the ball and ground is not instantaneous but occurs over a small yet finite interval. During this interval, complex physics governs the deformation of materials, conversion of kinetic energy to heat, and subtle atomic interactions.

![Figure 58](assets/17474452199621.jpg)
***Figure 58**: The messy middle between the pre- and post-collision manifolds.*

This "messy middle" represents indeterminancy in this system—a period where we cannot precisely predict the outcome using simplified mathematical models.

Formally, we can define an indeterminate interval using precise boundary points (Figure 59):

![Figure 59](assets/17474453366250.jpg)
***Figure 59*: The topology of a collision.*


1. **Br** (Beginning of release): The beginning of the ball's trajectory
2. **Bc** (Beginning of contact): The first possible moment the ball could make contact with the ground
3. **Bb** (Beginning of bounce): The moment when the ball begins moving away from the ground
4. **Bc1** (Beginning of contact 1): The next potential contact point, some point in the future

The intervals `[Br, Bc)` and `[Bb, Bc1)` can be determined through classical physics with ballistic equations. However, the critical interval `[Bc, Bb)` involves complex interactions that create indeterminancy in the temporal model.

### Temporal Mapping of Indeterminate Intervals

The challenge of indeterminancy lies in temporal mapping. For the intervals with deterministic physics, we can establish clear functions that map from interval space to time:

- The interval `[Br, Bc)` maps to `[time(Br), time(Bc))`
- The interval `[Bb, Bc1)` maps to `[time(Bb), time(Bc1))`

But for the indeterminate interval `[Bc, Bb)`, the mapping becomes problematic. We can express it as:

`[Bc, Bb) → [time(Bc), time(Bc) + ti)`

Where `ti` is the duration of the interaction process. The value of `ti` is unknown until observed, creating a "wrinkle in time" that affects all subsequent temporal mappings.

Let's define `tb = time(Bc) + ti`, then the mapping for `[Bb, Bc1)` becomes:

`[Bb, Bc1) → [tb, tb + time(Bc1) - time(Bb))`

## Observability

### The Collapse of Possibilities

The power of this approach is that we can write equations involving the post collision interval `[Bc, Bb)`, but we cannot evaluate them until the system is observed. Before observation, an indeterminate interval exists in a state of possibility; after observation, it exists as a specific instantiation with fixed temporal properties. After observation (Figure 60) the subsequent wordline may be mapped, up to the point of the next indeterminate interval.

![Figure 60](assets/17474456909294.jpg)
***Figure 60**: Once the indeterminate interval is observed, the worldline becomes known.*

The concept of observability addresses how indeterminate intervals resolve into determinate ones. Before observation, an indeterminate interval exists in a state of possibility; after observation, it exists as a specific instantiation with fixed temporal properties.

This phenomenon is analogous to quantum physics' wave function collapse, where multiple potential states exist simultaneously until measurement forces the system into a single state. In the temporal algebra, the observation of an indeterminate interval "collapses" its possible durations into a single, measurable duration.

Once [Bc, Bb) is observed and time(Bb) becomes known, the worldline can be fully mapped, and all subsequent intervals can be determined. This temporal resolution propagates through the system, allowing previously indeterminate projections to become determinate.

In practice, games and visual effects overcome this indeterminancy using a variety of strategies:

1. **Artificial Imposition**: In games and visual effects, we can artificially impose a fixed duration. For example, declaring that [Bc, Bb) always takes precisely 1/24 of a second simplifies computation while providing an acceptable approximation for many purposes.

2. **Pre-computation**: We can pre-compute simulations and store the observed duration. For instance, [Bc, Bb) might be observed to take 480 milliseconds in a specific simulation, which becomes a fixed property of the composition.

3. **Probabilistic Modeling**: We can model the interval as having a range of possible durations, each with an associated probability. This approach allows for more sophisticated handling of indeterminancy, especially in systems that need to account for variable outcomes.

4. **Lazy Evaluation**: We can design systems to defer the computation of indeterminate intervals until they are needed, at which point they are observed and resolved.


## Multiple Temporal Domains

### The Layered Nature of Time in Interactive Media

Interactive media systems must reconcile multiple notions of time that operate simultaneously but according to different rules. Referring back to the first chapter's "wheel of creation" we can identify at least three fundamental temporal domains that coexist in interactive media:

1. **Absolute Time (exogenous System Time)**: Absolute time refers to the actual clock time in which a system operates. It ensures that samples play at the correct rate, visual frames render smoothly, and that all processes maintain consistent timing. In digital systems, absolute time may be available from a system clock or may be accrue via a long count of regular hardware interrupts.

2. **Media Time (endogenous Structural Time)**: This domain represents the internal temporal structure of media elements. In music, it might be measured in measures, beats, and ticks; in animation, in frames or keypoints; in narrative, in scenes or chapters. Media time provides the organizational framework that gives content its coherence.

3. **Interaction Time (exogenous Event Time)**: The temporal flow of events driven by external agents—users, environments, or other systems. This domain is inherently indeterminate, as it depends on actions that cannot be fully predicted beforehand.

### Mapping Between Temporal Domains

The relationships between these domains are not fixed but dynamic, mediated by functions that map from one domain to another. These mapping functions act as transformation operators:

- `M(a,m)`: Absolute Time → Media Time
- `M(m,i)`: Media Time → Interaction Time
- `M(i,a)`: Interaction Time → Absolute Time

These mappings create a circuit of transformations that allow systems to maintain coherent temporal relationships despite the fundamentally different nature of each domain (Figure 61).

```mermaid
graph TD
    A[Absolute Time] --> B[Media Time]
    B --> C[Interaction Time]
    C --> A

    style A fill:#f9f,stroke:#333,stroke-width:2px
    style B fill:#bbf,stroke:#333,stroke-width:2px
    style C fill:#bfb,stroke:#333,stroke-width:2px
```
***Figure 61**: The circuit of time domains in an interactive system.*

In real applications, these mapping functions handle critical operations such as:

- `M(a,m)`: Converting system clock ticks to musical measures/beats or animation frames
- `M(m,i)`: Mapping structured media time to interaction events (e.g., when a musical measure triggers a game event)
- `M(i,a)`: Converting user interactions back to precise system timing (e.g., synchronizing user input with audio playback)

The coordination of these domains requires specialized mechanisms:

1. **Synchronization Points**: Designated moments where two or more temporal domains must align, similar to the boundary points `[Bc, Bb)` in the bouncing ball example.

2. **Adaptive Mapping Functions**: Functions that can adjust their transformation behavior based on observations of the system state.

3. **Temporal Buffers**: Mechanisms that compensate for discrepancies between domains, such as lookahead buffers or predictive models.

4. **Domain-Specific Controllers**: Specialized subsystems that manage time within a particular domain. For example:
   - A sample-accurate clock for absolute time
   - A metronome or sequencer for media time
   - An event queue for interaction time

### Indeterminancy Across Domains

Indeterminancy manifests differently across temporal domains:

- In absolute time, indeterminancy appears as timing jitter or variation in process execution
- In media time, it appears as conditional branches or variable-length segments
- In interaction time, it is the fundamental nature of the domain, where future states depend on choices that have not yet been made

Formalizing this multi-domain approach gives us the ability to reason about indeterminancy in a structured way. The mapping functions between domains become projections through a temporal topology, with indeterminate intervals representing regions where these projections are temporarily undefined until observation.

### Handling Indeterminancy in Media Systems

Media composition systems can address indeterminancy through several approaches:

1. **Artificial Imposition**: In games and visual effects, we can artificially impose a fixed duration. For example, declaring that [Bc, Bb) always takes precisely 1/24 of a second simplifies computation while providing an acceptable approximation for many purposes.

2. **Pre-computation**: We can pre-compute simulations and store the observed duration. For instance, [Bc, Bb) might be observed to take 480 milliseconds in a specific simulation, which becomes a fixed property of the composition.

3. **Probabilistic Modeling**: We can model the interval as having a range of possible durations, each with an associated probability. This approach allows for more sophisticated handling of indeterminancy, especially in systems that need to account for variable outcomes.

4. **Lazy Evaluation**: We can design systems to defer the computation of indeterminate intervals until they are needed, at which point they are observed and resolved.

Each of these approaches has implications for the design of temporal media systems and the types of interactions they can support.

## Quantum Electrodynamics and Temporal Indeterminancy

### Feynman's Perspective on Time

In Chapter 5, we introduced Feynman's interpretation of quantum electrodynamics, where positrons can be mathematically described as electrons moving backward in time. This conceptualization has profound implications for our understanding of temporal indeterminancy in interactive media systems.

Feynman's approach to QED offers several compelling parallels to this framework's treatment of indeterminate intervals:

1. **Superposition of Possibilities**: In quantum physics, particles exist in a superposition of possible states until measured. Similarly, the indeterminate interval `[Bc, Bb)` exists in a superposition of possible durations until observed.

2. **Path Integrals**: Feynman's path integral formulation suggests that a particle traveling from point `A` to point `B` takes all possible paths simultaneously, with each path having an associated probability amplitude. In the temporal framework, an indeterminate interval can be viewed as encompassing all possible temporal evolutions, each with its own probability.

3. **Observation Collapse**: Just as quantum measurement collapses the wave function into a specific state, the observation of an indeterminate interval collapses it into a specific duration.

### Sum Over Histories

Feynman's "sum over histories" approach provides a powerful mathematical model for handling indeterminancy. Applied to the bouncing ball example:

1. **Before Observation**: The interval `[Bc, Bb)` encompasses all possible interaction durations `ti`, each with an associated probability.

2. **Mathematical Representation**: We can express this as an integral over all possible durations:

   `P(t) = ∫ A(ti) e^(iS(ti)/ħ) dti`

   Where:
   - `A(ti)` represents the probability amplitude for a particular duration `ti`
   - `S(ti)` is the action associated with that duration (essentially the energy multiplied by time)
   - `ħ` is Planck's constant (a fundamental constant of quantum mechanics, representing the quantum of action)
   - `i` is the imaginary unit, making this a complex exponential function

   This equation, known as the path integral formulation, essentially sums the contributions from all possible temporal evolutions of the system, weighted by their probability amplitudes.

3. **Collapse Upon Observation**: When we observe the actual bounce, this integral collapses to a single value—the observed duration.

This quantum perspective suggest that indeterminant intervals in interactive media can be treated mathematically as probability distributions over possible temporal evolutions, rather than as gaps in the temporal model.

### Temporal Entanglement

Another relevant concept from quantum physics is entanglement—where particles become correlated in such a way that the quantum state of each particle cannot be described independently.

In interactive media, we encounter a form of temporal entanglement when multiple indeterminate intervals influence each other. For example, in a complex interactive narrative:

1. The resolution of one choice point (observation of one indeterminate interval) affects the probability distribution of subsequent choice points.

2. Some choice points may be "entangled" such that observing one immediately determines the outcome of another, without requiring separate observation.

3. The overall experience emerges from the complex interaction of these entangled temporal possibilities.

This framework allows us to model complex interactive systems where multiple indeterminate elements interact in non-trivial ways.

### Projection as Quantum Transformation

Returning to the temporal projection concept, we can now view it through a quantum lens. When we project one topology through another, we are effectively transforming the probability distributions associated with indeterminate intervals.

Consider a user interacting with a media system:

1. **Input Space**: The user's actions occupy a probability space of possible inputs.
2. **Projection Function**: The system applies a transformation to this probability space.
3. **Output Space**: The result is a new probability distribution over possible system states.

This quantum-inspired view provides a rigorous mathematical foundation for handling the inherent indeterminancy of interactive media. Rather than seeing indeterminancy as an obstacle to formal representation, we embrace it as a fundamental property that can be modeled with mathematical tools drawn from quantum theory. Like Feynman's positrons moving backward in time, what initially appears paradoxical—the inability to precisely determine the duration of an interaction before it occurs—becomes mathematically tractable when viewed through the appropriate theoretical lens.

## Physics Simulation in Temporal Algebra

### Bridging Simulation and Rendering Time Domains

The bouncing ball example explored earlier illustrates a fundamental challenge in physics simulation: the indeterminate interval during collision represents a discontinuity in temporal projection. In production rendering systems, these indeterminate intervals must be resolved into determinate ones for final image creation.

A simulation system operating within the temporal algebra framework would:

1. **Maintain Separate Temporal Topologies**: One for the continuous physics world and another for the discretized rendering world

2. **Define Projection Operations**: Map from simulation time (potentially variable timestep) to rendering time (typically fixed shutter intervals)

3. **Handle Temporal Discontinuities**: Apply appropriate sampling strategies around events like collisions

For adaptive timestep simulations, each simulation step creates a segment in the temporal topology with its own mapping function:
`simulation_step_i: [t_i, t_{i+1}) → [simulation_time(t_i), simulation_time(t_{i+1}))`

When projecting this non-uniform simulation timeline to rendering time, we apply the projection techniques from Chapter 5, ensuring accurate temporal relationships even when simulation steps and render samples don't align.

This approach allows rendering systems to accurately capture simulation events regardless of when they occur relative to frame boundaries, preserving temporal fidelity throughout the pipeline.

## Many Worlds

### Branching Temporal Structures

Interactive media experiences, particularly those involving user choice, naturally create branching temporal structures. Adventure games, interactive narratives, and decision-based simulations all involve multiple potential paths through a temporal space. These branching structures can be represented as directed graphs (Figure 61), where nodes correspond to decision points and edges represent potential paths. Each complete path through the graph represents a possible "world"—a coherent timeline that could exist depending on the choices made.

```mermaid
stateDiagram-v2
    [*] --> EnterTown: Ranger enters scene
    EnterTown --> ConversationWithBelle: Approach lady
    EnterTown --> EnterSaloon: Go through saloon doors
    ConversationWithBelle --> SheriffAppears: Take diamond ring
    ConversationWithBelle --> EnterSaloon: Reminisce about Galway
    SheriffAppears --> InJail: Hide the ring
    SheriffAppears --> EnterSaloon: Reminisce about Galway
    InJail --> End
    EnterSaloon --> End
    End --> [*]
```
***Figure 61**: An adventure's structure represented as a graph.*

All of these potential worlds exist simultaneously in the composition's possibility space. However, only one path is ultimately observed during any specific traversal of the content. This mirrors the concept of the "many-worlds" interpretation of quantum mechanics, where every possible outcome of a quantum event occurs in its own "world" or universe.

### Extending the Temporal Algebra to Graphs

To incorporate branching structures into the temporal algebra, we need a transformation that maps graph structures to interval-based topologies. Such a transformation allows application of all the temporal framework's tools.

The process involves:

1. Creating H-graphs to remove diamonds (converging and diverging paths)
2. Identifying chains that link start and end nodes
3. Removing chains to start a topology
4. Mapping the remaining graph to a topological representation

Let's illustrate this with a specific algorithm, first labeling nodes in the graph (Figure 62):

```mermaid
stateDiagram-v2
    [*] --> a_EnterTown: Ranger enters scene
    a_EnterTown --> b_ConversationWithBelle: Approach lady
    a_EnterTown --> e_EnterSaloon: Go through saloon doors
    b_ConversationWithBelle --> c_SheriffAppears: Take diamond ring
    b_ConversationWithBelle --> e_EnterSaloon: Reminisce about Galway
    c_SheriffAppears --> d_InJail: Hide the ring
    c_SheriffAppears --> e_EnterSaloon: Reminisce about Galway
    d_InJail --> f_End
    e_EnterSaloon --> f_End
    f_End --> [*]
```

### H-Graph Partitioning

To decompose this graph into a family of trees or "cactuses," we use a greedy heuristic that traverses the graph depth-first while growing trees from root-to-leaf chains.

#### Greedy Tree Extraction Algorithm

```text
Let G = (V, E) be the input directed acyclic graph.
Let S = set of all arcs (edges) in G.
Initialize T = [] (list of trees)

While S is not empty:
  1. Pick the arc e in S whose source node is earliest in a topological sort.
  2. Initialize a tree T' with arc e.
  3. Initialize a frontier with the target node of e.
  4. While frontier is not empty:
     a. Pop a node n.
     b. For each outgoing arc a from n in S:
        i. If a.target is not already in T',
           add a to T' and add a.target to the frontier.
        ii. Remove a from S.
  5. Add T' to T.
```

This produces a collection of subtrees covering all arcs in G, with no arc appearing in more than one tree. Each subtree corresponds to a coherent sequential path within the temporal graph.

#### Refinement Pass

To minimize the number of resulting H components and improve interpretability:

* Attempt to merge each tree T\_i into another tree T\_j if doing so results in an acyclic structure.
* Prefer merges that preserve existing path coherence or semantic unity (e.g., same narrative theme).

This pass builds toward a more minimal, readable H-graph decomposition.

### Annotated H-Graph Partition of Figure 62

To help ground this abstract procedure, we walk through an example using our previously labeled graph:

**Tree 1 (T1)**: Starts at `a_EnterTown` and follows `b_ConversationWithBelle` → `c_SheriffAppears` → `d_InJail` → `f_End`

**Tree 2 (T2)**: A shorter branch starting again at `a_EnterTown` → `e_EnterSaloon` → `f_End`

**Tree 3 (T3)**: An auxiliary merge path from `b_ConversationWithBelle` → `e_EnterSaloon` (linked to T2)

**Tree 4 (T4)**: From `c_SheriffAppears` → `e_EnterSaloon` (reusing an endpoint from T2)

The overlap at `e_EnterSaloon` and `f_End` is resolved by referencing the same endpoint across multiple trees, creating a set of overlapping but non-redundant linearizations.

```mermaid
flowchart TD
  subgraph T1
    a --> b --> c --> d --> f
  end

  subgraph T2
    a2[a] --> e --> f2[f]
  end

  subgraph T3
    b2[b] --> e2[e]
  end

  subgraph T4
    c2[c] --> e3[e]
  end
```
***Figure 63**: Partitioned H-Graph of the narrative structure.*

These H-components preserve the original graph's branching while allowing us to reason about them using temporal intervals. The disjoint trees can now be analyzed or recombined via algebraic operations.

![Figure 64](assets/17476279950010.jpg)
***Figure 64**: The partitioned graphs organized into an indeterminate topology.*

In the next section, we formalize how this decomposition allows us to map the structure into topological spaces and reason about them algebraically.

### Projections Across Possible Worlds

As observations propagate through the branching structure, projections can be made across different possible worlds. Each traversal describes one view on the many-worlds universe represented by the composition.

While all potential paths are valid within the composition, only one is observed during each interaction. This observed path becomes the "actual" timeline for that specific experience of the content.

For media composition systems, this framework provides a powerful way to represent and manipulate interactive content while maintaining mathematical rigor. It allows creators to design branching experiences that exhibit coherent temporal behavior across all possible paths.

## Applications to Interactive Media

### Real-time Interactive Systems

Real-time interactive systems must handle indeterminancy as a core feature rather than an edge case. Video games, virtual reality experiences, and interactive installations all involve user actions that cannot be predetermined. The temporal algebra developed in this book provides a framework for managing this indeterminancy while maintaining precise control over temporal relationships.

For example, in a video game:

1. Deterministic intervals represent scripted sequences and animations
2. Indeterminate intervals represent user interactions and physics simulations
3. Observation occurs through user input and system state changes
4. Projections map between game world time, simulation time, and presentation time

By formalizing these relationships, game engines can maintain consistent frame rates while accommodating unpredictable user actions.

### Adaptive Media

Adaptive media adjusts its content based on user behavior, environmental factors, or other dynamic inputs. Examples include personalized advertisements, responsive educational content, and context-aware applications.

Using the temporal algebra, adaptive media can be modeled as a network of potential temporal paths with transformation functions that select specific paths based on observed conditions. The indeterminate intervals correspond to decision points where the system evaluates which path to follow.

This approach allows adaptive media to maintain temporal coherence even as it dynamically reconfigures itself in response to changing conditions.

### Continuous Simulation Systems

Simulation systems, such as scientific models or digital twins, often deal with continuous processes that must be discretized for computation and presentation. The indeterminancy in these systems typically arises from complex interactions between simulated elements.

This framework allows these systems to:

1. Identify deterministic and indeterminate intervals within the simulation
2. Apply appropriate sampling strategies to each interval type
3. Propagate observations throughout the temporal structure
4. Maintain mathematical consistency across scale changes and variable time steps

By treating simulation time as a specialized form of media time, we can apply the full temporal algebra to create more robust and flexible simulation systems.

While the applications described above illustrate the theoretical potential of the framework, examining a historical system that anticipated many of these concepts can provide valuable insight. By analyzing such a system through the lens of the temporal algebra, we can both validate the mathematical approach and extract practical implementation strategies that have proven successful in real-world contexts.

## Practical Example: Interactive Music as Temporal Projections

### The iMUSE System as an Implementation of Temporal Algebra

One of the most successful early implementations of interactive temporal structures in media was LucasArts' iMUSE (Interactive Music Streaming Engine) system. Developed in the early 1990s, iMUSE solved many of the theoretical challenges we've discussed in this chapter through elegant practical mechanisms. Examining this system through the lens of the temporal algebra reveals how the abstract mathematical framework manifests in real-world applications.

#### Markers and Hooks: Formalizing Indeterminancy

The core innovation of iMUSE was its system of "markers" and "hooks" that connected game events to musical transitions. In the temporal algebra, we can model this as follows:

1. **Markers as Decision Points**: Markers embedded in MIDI sequences represented specific temporal coordinates (measure, beat, tick) where evaluation of indeterminate intervals could occur. Using the notation from earlier in the chapter, markers functioned as the boundary points `(Bc)` where indeterminancy begins.

2. **Hooks as Observational Collapse**: Hooks were logical variables set by the game that determined which path through the musical possibility space would be taken. When a marker was reached during playback, the system evaluated hook values to "observe" which of the potential futures would manifest. This corresponds directly to the concept of observation collapsing indeterminant intervals into determinate ones.

For example, in a game like *Monkey Island 2*, the music might contain a marker at measure 16, beat 1:

```c
// In the MIDI data (conceptual representation)
MARKER_ID = 42;  // At measure 16, beat 1
```

The game engine would set a hook value when the player enters a new location:

```c
// In game code
ImSetHook(currentMusic, HOOK_LOCATION, NEW_LOCATION_ID);
```

When the marker is reached, the hook value is observed, collapsing the indeterminate interval and selecting a specific musical branch.

#### Temporal Projections Through Musical Space

The iMUSE command set included operations like `MdJump` and `MdScan` that effectively implemented projections through temporal topologies:

```c
// Jump to a new position in musical time
MdJump(soundId, chunk, measure, beat, tick, sustainNotes);

// Scan through intervening events to reach a position
MdScan(soundId, chunk, measure, beat, tick);
```

These commands projected from one position in the musical timeline to another, with `MdJump` performing an immediate transformation and `MdScan` traversing the intervening space. In the temporal algebra, these operations correspond to projections between different sections of the temporal manifold.

What makes this particularly relevant to the discussion of indeterminancy is that these jumps could be conditional, based on the observation of game state:

```
[music plays] -> [marker reached] -> [hook value observed] -> [projection to new musical section]
```
```mermaid
stateDiagram-v2
    [*] --> Music_Plays
    Music_Plays --> Marker_Reached
    Marker_Reached --> Projection_To_New_Musical_Section: Hook Value Observed
    Projection_To_New_Musical_Section --> [*]
```

This chain of operations implements exactly the indeterminant interval resolution we described earlier in the chapter.

#### Compositional Implications: Authoring Potential Worlds

Composers working with iMUSE didn't create linear compositions but rather networks of potential musical paths—precisely the "many worlds" approach we've described. A typical iMUSE score included:

1. **Main Sequences**: Primary musical themes that could continue indefinitely
2. **Transition Sequences**: Short passages designed to bridge between different main sequences
3. **Variation Layers**: Instrumental parts that could be selectively enabled or disabled
4. **Decision Points**: Markers placed at musically appropriate positions for potential branching

This approach required composers to think topologically about music, considering how different segments could connect coherently regardless of the path taken through the musical space. In algebraic terms, they were authoring a complex temporal manifold with multiple potential projections, constrained by musical requirements.

#### Practical Resolution of the "Messy Middle"

The iMUSE system demonstrated pragmatic approaches to handling what we earlier called the "messy middle" of indeterminate intervals. Rather than attempting to model the full complexity of interaction physics (as in the bouncing ball example), iMUSE used several simplified but effective strategies:

1. **Musical Quantization**: Transitions were quantized to musical beats, ensuring that changes occurred only at musically appropriate moments.

2. **Pre-composed Transitions**: Rather than attempting to procedurally generate transitions, composers pre-authored transition segments for likely paths.

3. **Layered Approach**: By treating instruments as independent but synchronized layers, the system could change parts of the musical texture while maintaining continuity in others.

These strategies represent practical approximations of the theoretical framework we've developed, balancing mathematical rigor with artistic and computational constraints.

#### Multiple Time Domains

iMUSE managed multiple time domains simultaneously, as outlined earlier in this chapter:

1. **Absolute Time**: System-level timing for audio fidelity (333Hz interrupts)
2. **Media Time**: Musical measures, beats, and ticks for musically coherent navigation
3. **Interaction Time**: The temporal flow of player experience and game events

The system continuously performed projections between these domains, converting from game events to musical positions to sample-accurate playback timing. This multi-domain approach demonstrates how the abstract concept of projecting through temporal topologies manifests in practical media systems.

#### Mapping Interactive Narratives to Temporal Topologies: A Monkey Island Example

Let's examine a hypothetical scenario from Monkey Island 2 to demonstrating how the temporal framework applies to narrative structure. We'll examine how the mathematical formalism of H-graphs and temporal projection can represent a classic dramatic arc in the form of Freytag's Pyramid, with its well-defined narrative components: exposition, rising action, climax, falling action, and denouement. The scenario unfolds as follows:

1. Guybrush enters a beach scene (exposition)
2. As he approaches a palm tree, a monkey appears (inciting incident)
3. The monkey begins throwing coconuts at Guybrush (rising action/complication)
4. Guybrush proffers a banana to the monkey (climax)
5. The monkey accepts the banana and stops throwing coconuts (falling action)
6. The monkey leaves, allowing Guybrush to continue his journey (denouement)

This interactive scenario can be represented as a state chart with an indeterminate outcome at the climactic moment:

```mermaid
stateDiagram-v2
    [*] --> BeachEntry: Guybrush enters scene
    BeachEntry --> TreeApproach: Guybrush walks to tree
    TreeApproach --> MonkeyAppears: Proximity triggered
    MonkeyAppears --> CoconutThrowing: Monkey spots Guybrush
    CoconutThrowing --> OfferBanana: Guybrush uses banana
    OfferBanana --> MonkeyAccepts: Monkey takes banana
    OfferBanana --> MonkeyRefuses: Monkey throws harder
    MonkeyRefuses --> CoconutHits: Coconut hits Guybrush
    CoconutHits --> CoconutThrowing: Continue trying
    MonkeyAccepts --> MonkeyLeaves: Monkey satisfied
    MonkeyLeaves --> ExitBeach: Path cleared
    ExitBeach --> [*]
```

Each state in this diagram corresponds to both a narrative beat in Freytag's Pyramid and a node in our temporal topology. The music system would associate different musical elements with each state:

- **BeachEntry**: Main beach theme (gentle, ambient) - *Exposition*
- **TreeApproach**: Subtle tension added to beach theme - *Exposition*
- **MonkeyAppears**: Short "discovery" musical stinger - *Inciting Incident*
- **CoconutThrowing**: Comedic "danger" theme - *Rising Action*
- **OfferBanana**: Tension peak, musical pause - *Climax*
- **MonkeyAccepts/Refuses**: Resolve chord or tension chord - *Climactic Result*
- **CoconutHits**: Brief percussive stinger - *Setback*
- **MonkeyLeaves**: Short "success" fanfare - *Falling Action*
- **ExitBeach**: Return to ambient beach theme with "progress" motif - *Denouement*

### Applying H-Graph Decomposition to Narrative Structure

To apply the temporal framework to this structure, we need to transform it using the H-graph methodology. First, we identify the nodes:

- a: BeachEntry
- b: TreeApproach
- c: MonkeyAppears
- d: CoconutThrowing
- e: OfferBanana (climactic moment)
- f: MonkeyAccepts
- g: MonkeyRefuses
- h: CoconutHits
- i: MonkeyLeaves
- j: ExitBeach

The H-graph decomposition yields two primary paths and a recursive loop:

1. **Success Path**: [a,b) → [b,c) → [c,d) → [d,e) → [e,f) → [f,i) → [i,j)
2. **Failure Path**: [a,b) → [b,c) → [c,d) → [d,e) → [e,g) → [g,h)
3. **Retry Loop**: [h,d)

Mathematically, we can express the narrative progression through these intervals using a projection function P that maps from narrative intervals to their musical and temporal expressions:

For each interval `[n₁,n₂)`, we define:

`P([n₁,n₂)) = { musical_theme(n₁), temporal_duration([n₁,n₂)) }`

For example:
`P([a,b)) = { "beachTheme", t_beach_exploration }`
`P([d,e)) = { "dangerTheme", t_coconut_throwing }`

### Narrative Structure as Temporal Topology

The dramatic arc of Freytag's Pyramid can be formally represented in our temporal framework as a sequence of intervals with associated narrative functions:

1. **Exposition**: [a,c) = [a,b) ∪ [b,c)
   - Narrative function: Establish setting and character

2. **Rising Action**: [c,e) = [c,d) ∪ [d,e)
   - Narrative function: Introduce and escalate conflict

3. **Climax**: [e,e+ε)
   - Narrative function: Present moment of decision/highest tension
   - Note: This is a small but crucial interval representing the climactic moment

4. **Falling Action**:
   - Success path: [f,i)
   - Failure path: [g,h)
   - Narrative function: Present consequences of climactic action

5. **Denouement**: [i,j)
   - Narrative function: Resolve story and establish new equilibrium

The critical indeterminate interval in this narrative occurs at point e (OfferBanana), where the story branches based on an observation:

`[e,?) where ? ∈ {f,g}`

This interval remains indeterminate until the system observes whether the offer succeeds or fails. Using our formalism from earlier in the chapter:

- Bc (Beginning of contact): The moment Guybrush offers the banana
- Bb (Beginning of bounce): The moment the narrative resolves the offer (acceptance or rejection)
- [Bc,Bb): The indeterminate interval representing the offer's outcome

### Temporal Projections Across Narrative Domains

The music system in our example must perform projections between three temporal domains:

1. **Narrative Time**: The sequence of story events
2. **Musical Time**: Measures, beats, and phrases
3. **Presentation Time**: Real-time audio playback

For the climactic moment (OfferBanana), these projections are particularly important. The musical composition might include multiple potential paths from this point:

- A triumphant resolution theme for the MonkeyAccepts branch
- A tension-increasing motif for the MonkeyRefuses branch

At the moment of observation (when the game determines the outcome), the system performs a projection from narrative time to musical time:

`T(narrative→music): [e,?) → [measure_x, ?)`

Where measure_x is the precise musical position where the branching occurs. This is implemented in the iMUSE system through markers placed at these critical musical positions.

### Mathematical Representation of the Retry Loop

The retry loop [h,d) represents a common pattern in interactive narratives. When mapped to temporal domains, this creates a projection back to an earlier narrative state:

`P([h,d)) = Project(narrative_state_h → narrative_state_d)`

This projection preserves certain state elements (Guybrush's knowledge, inventory minus one banana) while resetting others (position, monkey's coconut-throwing state).

Formally, we can express this as:

`narrative_state_d' = narrative_state_d ⊕ Δ(narrative_state_h)`

Where:
- narrative_state_d' is the new state after looping back
- ⊕ is a state composition operator
- Δ(narrative_state_h) represents the differential knowledge gained in state h

### Narrative State Vector and Temporal Consistency

Each node in our H-graph carries a narrative state vector that includes:

- Character positions and states
- Environment conditions
- Player knowledge
- Inventory items
- Narrative flags and variables

As a player traverses the narrative graph, the temporal algebra ensures consistency of this state vector despite the indeterminate path. For instance, the inventory cannot contain the banana after it has been successfully used, and this constraint must be maintained across all possible projections.

Using Allen's interval algebra relations from Chapter 4, we can formally express narrative causal constraints:

- Before(a,c): Guybrush must enter the beach before the monkey appears
- Meets(e,f): The banana offer immediately precedes the monkey's acceptance
- Before(e,i): The climactic offer must occur before the monkey leaves

These relationships enforce that narrative progression follows causally valid sequences, regardless of the specific path taken through the possibility space.

### Observation and Indeterminacy in Interactive Narrative

The central insight of our framework is that interactive narratives contain fundamental indeterminate intervals that collapse into determinate ones upon observation. In the Monkey Island example, the outcome of offering the banana is indeterminate until observed:

- If the player has properly acquired the banana earlier and uses it correctly, the observation collapses to MonkeyAccepts
- If the player lacks the banana or uses it incorrectly, the observation collapses to MonkeyRefuses

This observation process can be mathematically represented as:

O([e,?)) → [e,specific_outcome)

Where O is an observation function that evaluates game state and player actions to determine which determinate interval replaces the indeterminate one.

### Connecting Musical and Narrative Projection

The iMUSE system implements this observation and projection model through its markers and hooks mechanism. When the narrative system observes the outcome of the banana offering, it sets appropriate hook values:

narrative_observation → hook_values → musical_projection

For example, when Guybrush successfully offers the banana:

1. The system observes success in the narrative domain
2. It sets HOOK_MONKEY_STATE = ACCEPTS
3. At the next marker (corresponding to our Bc point), it evaluates this observation
4. It projects from the current position in the tension theme to the appropriate position in the success theme

Similarly, if the offer fails:

1. The system observes failure in the narrative domain
2. It sets HOOK_MONKEY_STATE = REFUSES
3. At the next marker, it evaluates this observation
4. It projects from the tension theme to the danger theme with increased intensity

### Dramatic Pacing as Temporal Transformation

The narrative experience involves transformations of perceived time. As tension rises during the climactic banana offering, the perceived pacing of events might change. We can model this as a transformation from objective time to dramatically-perceived time:

H_dramatic = [ s  0 ]
             [ 0  1 ]

Where s is a scaling factor that represents dramatic time compression or expansion. During the climactic moment, time might subjectively "slow down" (s < 1) to heighten tension, while during the denouement, time might "speed up" (s > 1) to quickly resolve the scene.

### Conclusion: Narrative Structure as Temporal Algebra

The Monkey Island example demonstrates how our temporal algebra framework provides a formal mathematical foundation for interactive storytelling. By mapping Freytag's dramatic structure to intervals in our H-graph, and by representing narrative branches as observations of indeterminate intervals, we create a rigorous model for understanding interactive narrative.

This approach allows us to:

1. Maintain narrative coherence across multiple possible paths
2. Ensure causal consistency in an interactive environment
3. Synchronize musical elements with narrative progression
4. Formally reason about dramatic structure and pacing

The iMUSE system intuitively implemented many of these concepts for musical accompaniment, but our temporal algebra extends these principles to the broader narrative structure. By treating interactive storytelling as a problem of temporal projection across multiple domains, we provide a mathematical framework that unifies narrative theory with the technical implementation of interactive systems.

### Lessons for Modern Systems

The iMUSE system, despite being developed decades ago with limited computing resources, embodied many of the mathematical principles we've formalized in this chapter. Modern interactive media systems can build upon these foundations with additional capabilities:

1. **Probabilistic Branching**: Rather than binary decision points, systems can implement weighted probabilities for different paths.

2. **Continuous Parameter Spaces**: Instead of discrete branches, parameters can be continuously varied based on input.

3. **Machine Learning Integration**: Neural networks can learn optimal projections between temporal spaces based on user experience data.

4. **Higher-Dimensional Control**: Modern systems can extend beyond musical time to manipulate spatial, timbral, and narrative dimensions simultaneously.

By understanding historical implementations like iMUSE through the lens of temporal algebra, we can appreciate both the practical wisdom embedded in these systems and the opportunities for extending their capabilities with this more comprehensive mathematical framework.

## Conclusion

The challenge of indeterminancy in temporal media systems reflects a fundamental truth about reality: time does not always unfold in predictable, linear ways. By incorporating concepts from quantum mechanics, graph theory, and probability into the temporal algebra, we can create media systems that embrace this complexity rather than avoiding it.

The indeterminant interval—the "wrinkle in time" where multiple possible futures exist simultaneously—is not a bug in the mathematical framework but a feature that enables more expressive and powerful temporal representations. This is powerfully illustrated by the iMUSE system we examined, which despite the technological constraints of its era, managed to implement many of the principles this algebra formalizes.

The historical success of systems like iMUSE validates the approach. What composers and engineers accomplished through intuition and practical problem-solving, we have now formalized into a rigorous mathematical framework. This formalization provides several advantages:

1. It allows us to reason about temporal structures with mathematical precision
2. It enables systematic evaluation of different approaches to handling indeterminancy
3. It offers a shared language for discussing interactive temporal media across disciplines
4. It provides a foundation for extending these concepts to new domains and applications

As media becomes increasingly interactive, adaptive, and personalized, the ability to formally represent and manipulate indeterminant temporal structures will become essential for next-generation composition systems. The framework presented in this chapter provides a foundation for these capabilities, extending the mathematical rigor of previous chapters to embrace the messy, complex, and fundamentally indeterminate nature of interactive experiences across multiple temporal domains.

In the next chapter, we will explore additional practical applications of this complete temporal algebra, showing how it can be implemented in contemporary systems to solve concrete problems in media composition beyond interactive music.

______________________________________________________

## References and Further Reading

### Mathematical Foundations

- Allen, J. F. (1983). "**Maintaining Knowledge about Temporal Intervals.**" *Communications of the ACM*, 26(11), 832–843.
- Roberts, L. (1963). "Machine Perception of Three-Dimensional Solids."
- Kripke, Saul A. **Semantical Considerations on Modal Logic.** *Acta Philosophica Fennica* 16 (1963): 83–94.
- Porter, T. and Duff, T. (1984). "**Compositing Digital Images.**" *SIGGRAPH Computer Graphics*, 18(3), 253–259.
- Grüninger, Michael and Li, Zhuojun (2017). "**The Time Ontology of Allen’s Interval Algebra**", *24th International Symposium on Temporal Representation and Reasoning* (TIME 2017). Editors: Sven Schewe, Thomas Schneider, and Jef Wijsen; Article No.16; pp.16:1–16:16, *Leibniz International Proceedings in Informatics*. https://drops.dagstuhl.de/storage/00lipics/lipics-vol090-time2017/LIPIcs.TIME.2017.16/LIPIcs.TIME.2017.16.pdf
- J. van Benthem. **The Logic of Time: A Model-Theoretic Investigation into the Varieties of Temporal Ontology and Temporal Discourse.** *Springer Verlag*, 1983, revised 1991.

### Media Systems

- *OpenTimelineIO*: http://opentimeline.io, *Academy Software Foundation*
- Ohanian, Thomas A., "**Digital Nonlinear Editing: New Approaches to Editing Film and Video**", *Focal Press*, 1993

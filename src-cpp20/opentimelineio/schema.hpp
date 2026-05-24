#pragma once
#include "core.hpp"
#include <string>
#include <vector>
#include <memory>
#include <optional>
#include <unordered_map>

// OpenTimelineIO Schema Types
//
// Schema types representing timeline objects: clips, gaps, tracks, stacks, etc.
//
// Ported from wrinkles/src/opentimelineio/schema.zig

namespace otio {

// Forward declarations
struct Parameter;
struct ParameterVarying;

// ============================================================================
// Media References
// ============================================================================

/// A reference that points at some reference via a string address
struct ExternalReference {
    std::string target_uri;

    ExternalReference() = default;
    explicit ExternalReference(std::string uri) : target_uri(std::move(uri)) {}
};

/// A procedural signal (placeholder for signal generator)
struct SignalReference {
    // TODO: Implement signal generator when sampling module is ported
    // sampling::SignalGenerator signal_generator;
};

/// An opaque/empty reference
struct EmptyReference {
};

/// Information about the media that this clip is cutting into the timeline
using MediaDataReference = std::variant<
    ExternalReference,
    SignalReference,
    EmptyReference
>;

inline const MediaDataReference EMPTY_REF = MediaDataReference{EmptyReference{}};

/// Media reference with bounds and discrete info
struct MediaReference {
    MediaDataReference ref = EMPTY_REF;

    /// Bounds of the media space continuous time
    std::optional<ContinuousInterval> bounds_s;

    // TODO: Implement when sampling module is ported
    // std::optional<sampling::SampleIndexGenerator> discrete_info;

    bool interpolating = false;

    MediaReference() = default;
};

// ============================================================================
// Parameter System (for effects/metadata)
// ============================================================================

enum class ParameterDomain {
    time,
    picture,
    audio,
    metadata,
};

struct ParameterVarying {
    ParameterDomain domain;
    Topology mapping;

    ParameterVarying(ParameterDomain d, Topology m)
        : domain(d), mapping(std::move(m)) {}
};

using ParameterMap = std::unordered_map<std::string, std::shared_ptr<ParameterVarying>>;

// ============================================================================
// Clip
// ============================================================================

/// Clip with an implied media reference
struct Clip {
    /// Identifier name
    std::optional<std::string> name;

    /// A trim on the media space, in the media coordinate system
    std::optional<ContinuousInterval> bounds_s;

    /// Information about the media this clip cuts into the track
    MediaReference media;

    /// Optional parameters (effects, metadata)
    std::optional<ParameterMap> parameters;

    // ---- Construction ----

    Clip() = default;

    explicit Clip(std::string n) : name(std::move(n)) {}

    Clip(std::string n, ContinuousInterval bounds)
        : name(std::move(n)), bounds_s(bounds) {}

    // ---- Methods ----

    /// Compute the bounds of the specified target space
    ContinuousInterval bounds_of(SpaceLabel target_space) const {
        auto maybe_bounds_s = bounds_s.has_value() ? bounds_s : media.bounds_s;

        if (!maybe_bounds_s.has_value()) {
            throw std::runtime_error("Clip has no bounds");
        }

        auto bounds = *maybe_bounds_s;

        switch (target_space) {
            case SpaceLabel::media:
            case SpaceLabel::presentation:
                return bounds;
            default:
                throw std::runtime_error("Unsupported space for Clip");
        }
    }

    /// Build a topology that maps from presentation space to media space
    Topology topology() const {
        if (!bounds_s.has_value()) {
            throw std::runtime_error("Clip has no bounds - cannot build topology");
        }

        return Topology::init_identity(*bounds_s);
    }

    /// Get list of spaces this object has
    std::vector<SpaceReference> spaces() const {
        std::vector<SpaceReference> result;
        result.push_back(SpaceReference{const_cast<Clip*>(this), SpaceLabel::presentation});
        result.push_back(SpaceReference{const_cast<Clip*>(this), SpaceLabel::media});
        return result;
    }
};

// ============================================================================
// Gap
// ============================================================================

/// Represents a space in the timeline without media
struct Gap {
    std::optional<std::string> name;
    Ordinate duration_seconds;

    Gap() : duration_seconds(Ordinate::init(0.0)) {}

    explicit Gap(Ordinate duration) : duration_seconds(duration) {}

    Gap(std::string n, Ordinate duration)
        : name(std::move(n)), duration_seconds(duration) {}

    /// Build topology (identity over duration)
    Topology topology() const {
        return Topology::init_identity(
            ContinuousInterval{
                Ordinate::ZERO(),
                duration_seconds
            }
        );
    }

    /// Get bounds
    ContinuousInterval bounds_of(SpaceLabel target_space) const {
        if (target_space == SpaceLabel::presentation) {
            return ContinuousInterval{Ordinate::ZERO(), duration_seconds};
        }
        throw std::runtime_error("Gap only has presentation space");
    }

    /// Get list of spaces
    std::vector<SpaceReference> spaces() const {
        std::vector<SpaceReference> result;
        result.push_back(SpaceReference{const_cast<Gap*>(this), SpaceLabel::presentation});
        return result;
    }
};

// ============================================================================
// Warp
// ============================================================================

/// A warp is an additional nonlinear transformation between parent and child
struct Warp {
    std::optional<std::string> name;
    ComposedValueRef child;
    Topology transform;
    bool interpolating = false;

    Warp(ComposedValueRef c, Topology t)
        : child(c), transform(std::move(t)) {}

    /// Get the transform (warp returns its stored transform directly)
    Topology topology() const {
        return transform.clone();
    }

    /// Get bounds in specified space
    ContinuousInterval bounds_of(SpaceLabel target_space) const {
        if (target_space == SpaceLabel::presentation) {
            return transform.input_bounds();
        }
        throw std::runtime_error("Warp only has presentation space");
    }

    /// Get list of spaces
    std::vector<SpaceReference> spaces() const {
        std::vector<SpaceReference> result;
        result.push_back(SpaceReference{const_cast<Warp*>(this), SpaceLabel::presentation});
        return result;
    }
};

// ============================================================================
// Track
// ============================================================================

/// A container in which each contained item is right-met over time
struct Track {
    std::optional<std::string> name;
    std::vector<ComposedValueRef> children;

    Track() = default;

    explicit Track(std::string n) : name(std::move(n)) {}

    Track(std::string n, std::vector<ComposedValueRef> c)
        : name(std::move(n)), children(std::move(c)) {}

    /// Add a child to the track
    void append_child(ComposedValueRef child) {
        children.push_back(child);
    }

    /// Construct the topology mapping the output to the intrinsic space
    Topology topology() const {
        // Build the bounds by extending over all children
        std::optional<ContinuousInterval> maybe_bounds;

        for (auto const& child : children) {
            // Get child topology
            auto child_topo = detail::get_topology(child);
            auto child_bound = child_topo.input_bounds();

            if (maybe_bounds.has_value()) {
                maybe_bounds = extend(*maybe_bounds, child_bound);
            } else {
                maybe_bounds = child_bound;
            }
        }

        // Unpack the optional
        auto result_bound = maybe_bounds.value_or(ContinuousInterval::ZERO());

        return Topology::init_identity(result_bound);
    }

    /// Builds a transform from the previous child space to the one passed in
    Topology transform_to_child(SpaceReference const& child_space_ref) const {
        if (!child_space_ref.child_index.has_value()) {
            throw std::runtime_error("No child index on child space reference");
        }

        size_t child_index = *child_space_ref.child_index;

        // Get the previous child (child_index - 1)
        if (child_index == 0) {
            throw std::runtime_error("Cannot get transform to child 0 (no previous child)");
        }

        auto const& prev_child = children[child_index - 1];
        auto child_range = detail::get_bounds_of(prev_child, SpaceLabel::presentation);
        auto child_duration = child_range.duration();

        // The transform to the next child space compensates for this duration
        return Topology::init_affine(
            MappingAffine{
                ContinuousInterval{child_duration, Ordinate::INF()},
                AffineTransform1D{child_duration.neg(), Ordinate::ONE()}
            }
        );
    }

    /// Get bounds in specified space
    ContinuousInterval bounds_of(SpaceLabel target_space) const {
        auto topo = topology();

        switch (target_space) {
            case SpaceLabel::presentation:
                return topo.input_bounds();
            case SpaceLabel::intrinsic:
                return topo.output_bounds();
            default:
                throw std::runtime_error("Unsupported space for Track");
        }
    }

    /// Get list of spaces
    std::vector<SpaceReference> spaces() const {
        std::vector<SpaceReference> result;
        result.push_back(SpaceReference{const_cast<Track*>(this), SpaceLabel::presentation});
        result.push_back(SpaceReference{const_cast<Track*>(this), SpaceLabel::intrinsic});
        return result;
    }
};

// ============================================================================
// Stack
// ============================================================================

/// Children of a stack are simultaneous in time
struct Stack {
    std::optional<std::string> name;
    std::vector<ComposedValueRef> children;

    Stack() = default;

    explicit Stack(std::string n) : name(std::move(n)) {}

    Stack(std::string n, std::vector<ComposedValueRef> c)
        : name(std::move(n)), children(std::move(c)) {}

    /// Add a child to the stack
    void append_child(ComposedValueRef child) {
        children.push_back(child);
    }

    /// Build topology (identity over the bounds of all children)
    Topology topology() const {
        // Build the bounds by extending over all children
        std::optional<ContinuousInterval> maybe_bounds;

        for (auto const& child : children) {
            auto child_topo = detail::get_topology(child);
            auto child_bound = child_topo.input_bounds();

            if (maybe_bounds.has_value()) {
                maybe_bounds = extend(*maybe_bounds, child_bound);
            } else {
                maybe_bounds = child_bound;
            }
        }

        if (maybe_bounds.has_value()) {
            return Topology::init_affine(
                MappingAffine{*maybe_bounds, AffineTransform1D::IDENTITY()}
            );
        } else {
            return Topology{};  // Empty topology
        }
    }

    /// Get bounds in specified space
    ContinuousInterval bounds_of(SpaceLabel target_space) const {
        auto topo = topology();

        switch (target_space) {
            case SpaceLabel::presentation:
                return topo.input_bounds();
            case SpaceLabel::intrinsic:
                return topo.output_bounds();
            default:
                throw std::runtime_error("Unsupported space for Stack");
        }
    }

    /// Get list of spaces
    std::vector<SpaceReference> spaces() const {
        std::vector<SpaceReference> result;
        result.push_back(SpaceReference{const_cast<Stack*>(this), SpaceLabel::presentation});
        result.push_back(SpaceReference{const_cast<Stack*>(this), SpaceLabel::intrinsic});
        return result;
    }
};

// ============================================================================
// Timeline
// ============================================================================

/// Top level object containing tracks
struct Timeline {
    std::optional<std::string> name;
    Stack tracks;

    // TODO: Add discrete_info and time_spaces when sampling module is ported

    Timeline() = default;

    explicit Timeline(std::string n) : name(std::move(n)) {}

    Timeline(std::string n, Stack t)
        : name(std::move(n)), tracks(std::move(t)) {}

    /// Get the topology of the timeline (delegates to tracks)
    Topology topology() const {
        return tracks.topology();
    }

    /// Get bounds
    ContinuousInterval bounds_of(SpaceLabel target_space) const {
        return tracks.bounds_of(target_space);
    }

    /// Get list of spaces
    std::vector<SpaceReference> spaces() const {
        std::vector<SpaceReference> result;
        result.push_back(SpaceReference{const_cast<Timeline*>(this), SpaceLabel::presentation});
        result.push_back(SpaceReference{const_cast<Timeline*>(this), SpaceLabel::intrinsic});
        return result;
    }
};

// ============================================================================
// ComposedValueRef Helper Implementations
// ============================================================================

namespace detail {

inline std::optional<std::string> get_name(ComposedValueRef const& ref) {
    return std::visit([](auto const* ptr) -> std::optional<std::string> {
        return ptr->name;
    }, ref);
}

inline Topology get_topology(ComposedValueRef const& ref) {
    return std::visit([](auto const* ptr) -> Topology {
        if constexpr (std::is_same_v<std::decay_t<decltype(*ptr)>, Warp>) {
            // Warp returns its stored transform directly
            return ptr->transform.clone();
        } else {
            return ptr->topology();
        }
    }, ref);
}

inline ContinuousInterval get_bounds_of(
    ComposedValueRef const& ref,
    SpaceLabel target_space
) {
    return std::visit([target_space](auto const* ptr) -> ContinuousInterval {
        return ptr->bounds_of(target_space);
    }, ref);
}

inline std::vector<SpaceReference> get_spaces(ComposedValueRef const& ref) {
    return std::visit([](auto const* ptr) -> std::vector<SpaceReference> {
        return ptr->spaces();
    }, ref);
}

} // namespace detail

} // namespace otio

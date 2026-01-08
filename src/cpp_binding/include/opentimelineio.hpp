// opentimelineio.hpp - C++ API for OpenTimelineIO/Wrinkles
//
// This is a modern C++ (C++17) wrapper around the Zig OTIO implementation,
// providing idiomatic C++ access to timeline data structures and temporal
// projection operations.

#ifndef OPENTIMELINEIO_HPP
#define OPENTIMELINEIO_HPP

#include <cstdint>
#include <cstddef>
#include <string>
#include <optional>
#include <vector>
#include <stdexcept>
#include <limits>
#include <ostream>
#include <sstream>
#include <iomanip>
#include <iterator>

// Include C API
extern "C" {
#include "opentimelineio_c.h"
}

namespace otio {

// ============================================================================
// Exception Classes
// ============================================================================

class OtioError : public std::runtime_error {
public:
    explicit OtioError(const std::string& msg) : std::runtime_error(msg) {}
};

class FileNotFoundError : public OtioError {
public:
    explicit FileNotFoundError(const std::string& path)
        : OtioError("File not found: " + path) {}
};

class ParseError : public OtioError {
public:
    explicit ParseError(const std::string& msg)
        : OtioError("Parse error: " + msg) {}
};

class InvalidOperationError : public OtioError {
public:
    explicit InvalidOperationError(const std::string& msg)
        : OtioError("Invalid operation: " + msg) {}
};

// ============================================================================
// Time Types
// ============================================================================

/// A single point in continuous time (wraps a float)
struct Ordinate {
    float value;

    // Construction
    constexpr Ordinate() : value(0.0f) {}
    constexpr explicit Ordinate(float v) : value(v) {}
    constexpr explicit Ordinate(double v) : value(static_cast<float>(v)) {}

    // Named constructors
    static constexpr Ordinate zero() { return Ordinate(0.0f); }
    static constexpr Ordinate one() { return Ordinate(1.0f); }
    static constexpr Ordinate inf() { return Ordinate(std::numeric_limits<float>::infinity()); }
    static constexpr Ordinate neg_inf() { return Ordinate(-std::numeric_limits<float>::infinity()); }

    // Conversion
    constexpr float as_float() const { return value; }
    constexpr double as_double() const { return static_cast<double>(value); }

    // Arithmetic
    constexpr Ordinate operator+(Ordinate other) const { return Ordinate(value + other.value); }
    constexpr Ordinate operator-(Ordinate other) const { return Ordinate(value - other.value); }
    constexpr Ordinate operator*(Ordinate other) const { return Ordinate(value * other.value); }
    constexpr Ordinate operator/(Ordinate other) const { return Ordinate(value / other.value); }
    constexpr Ordinate operator-() const { return Ordinate(-value); }

    // Comparison
    constexpr bool operator==(Ordinate other) const { return value == other.value; }
    constexpr bool operator!=(Ordinate other) const { return value != other.value; }
    constexpr bool operator<(Ordinate other) const { return value < other.value; }
    constexpr bool operator<=(Ordinate other) const { return value <= other.value; }
    constexpr bool operator>(Ordinate other) const { return value > other.value; }
    constexpr bool operator>=(Ordinate other) const { return value >= other.value; }

    // Queries
    constexpr bool is_inf() const {
        return value == std::numeric_limits<float>::infinity()
            || value == -std::numeric_limits<float>::infinity();
    }
};

/// Stream output for Ordinate
inline std::ostream& operator<<(std::ostream& os, Ordinate ord) {
    return os << ord.value << "s";
}

/// A range in continuous time
struct ContinuousInterval {
    Ordinate start;
    Ordinate end;

    // Construction
    constexpr ContinuousInterval() : start(Ordinate::zero()), end(Ordinate::zero()) {}
    constexpr ContinuousInterval(Ordinate s, Ordinate e) : start(s), end(e) {}
    constexpr ContinuousInterval(float s, float e)
        : start(Ordinate(s)), end(Ordinate(e)) {}

    // From C API type
    explicit ContinuousInterval(otio_ContinuousInterval c)
        : start(Ordinate(c.start)), end(Ordinate(c.end)) {}

    // To C API type
    otio_ContinuousInterval to_c() const {
        return {start.as_float(), end.as_float()};
    }

    // Named constructors
    static constexpr ContinuousInterval from_start_duration(Ordinate s, Ordinate dur) {
        return ContinuousInterval(s, Ordinate(s.value + dur.value));
    }

    static constexpr ContinuousInterval infinite() {
        return ContinuousInterval(Ordinate::neg_inf(), Ordinate::inf());
    }

    // Properties
    constexpr Ordinate duration() const { return Ordinate(end.value - start.value); }
    constexpr bool is_empty() const { return start == end; }
    constexpr bool is_infinite() const { return start.is_inf() || end.is_inf(); }

    // Queries
    constexpr bool contains(Ordinate ord) const {
        return ord >= start && ord < end;
    }

    constexpr bool overlaps(const ContinuousInterval& other) const {
        return start < other.end && other.start < end;
    }

    // Comparison
    constexpr bool operator==(const ContinuousInterval& other) const {
        return start == other.start && end == other.end;
    }
    constexpr bool operator!=(const ContinuousInterval& other) const {
        return !(*this == other);
    }
};

/// Stream output for ContinuousInterval
inline std::ostream& operator<<(std::ostream& os, const ContinuousInterval& interval) {
    return os << "[" << interval.start << ", " << interval.end << ")";
}

/// For exact frame rates (e.g., 24000/1001 for 23.976fps)
struct Rational {
    uint32_t numerator;
    uint32_t denominator;

    // Construction
    constexpr Rational() : numerator(0), denominator(1) {}
    constexpr Rational(uint32_t num, uint32_t den = 1)
        : numerator(num), denominator(den) {}

    // From C API type
    explicit Rational(otio_Rational r) : numerator(r.num), denominator(r.den) {}

    // To C API type
    otio_Rational to_c() const { return {numerator, denominator}; }

    // Common rates
    static constexpr Rational fps_24() { return Rational(24, 1); }
    static constexpr Rational fps_23_976() { return Rational(24000, 1001); }
    static constexpr Rational fps_25() { return Rational(25, 1); }
    static constexpr Rational fps_29_97() { return Rational(30000, 1001); }
    static constexpr Rational fps_30() { return Rational(30, 1); }
    static constexpr Rational fps_48() { return Rational(48, 1); }
    static constexpr Rational fps_60() { return Rational(60, 1); }

    // Audio rates
    static constexpr Rational audio_44100() { return Rational(44100, 1); }
    static constexpr Rational audio_48000() { return Rational(48000, 1); }
    static constexpr Rational audio_96000() { return Rational(96000, 1); }

    // Conversion
    constexpr double as_double() const {
        return static_cast<double>(numerator) / static_cast<double>(denominator);
    }

    constexpr float as_float() const {
        return static_cast<float>(numerator) / static_cast<float>(denominator);
    }

    // Comparison
    constexpr bool operator==(const Rational& other) const {
        // Cross multiplication for exact comparison
        return static_cast<uint64_t>(numerator) * other.denominator
            == static_cast<uint64_t>(other.numerator) * denominator;
    }
};

/// Stream output for Rational
inline std::ostream& operator<<(std::ostream& os, const Rational& r) {
    if (r.denominator == 1) {
        return os << r.numerator << " hz";
    }
    return os << r.numerator << "/" << r.denominator << " hz";
}

/// Describes discrete sampling (frame rate, audio sample rate)
struct SampleIndexGenerator {
    Rational sample_rate_hz;
    size_t start_index;

    // Construction
    SampleIndexGenerator() : sample_rate_hz(), start_index(0) {}
    SampleIndexGenerator(Rational rate, size_t start = 0)
        : sample_rate_hz(rate), start_index(start) {}

    // From C API type
    explicit SampleIndexGenerator(otio_DiscreteDatasourceIndexGenerator g)
        : sample_rate_hz(g.sample_rate_hz), start_index(g.start_index) {}

    // To C API type
    otio_DiscreteDatasourceIndexGenerator to_c() const {
        return {sample_rate_hz.to_c(), start_index};
    }

    // Compute sample index at a given time ordinate
    size_t index_at(Ordinate time) const {
        double samples_per_second = sample_rate_hz.as_double();
        return start_index + static_cast<size_t>(time.as_double() * samples_per_second);
    }

    // Compute time ordinate at a given sample index
    Ordinate time_at(size_t index) const {
        double samples_per_second = sample_rate_hz.as_double();
        return Ordinate(static_cast<float>((index - start_index) / samples_per_second));
    }
};

// ============================================================================
// Enumerations
// ============================================================================

/// Composable type enumeration matching C API
enum class ComposableType {
    Timeline,
    Stack,
    Track,
    Clip,
    Gap,
    Warp,
    Transition,
    Error
};

/// Media data type enumeration
enum class MediaDataType {
    Uri,
    Signal,
    Null
};

/// Domain enumeration
enum class Domain {
    Time,
    Picture,
    Audio,
    Metadata,
    Other
};

/// Temporal space enumeration
enum class TemporalSpace {
    Presentation,
    Media
};

// ============================================================================
// Forward Declarations
// ============================================================================

class Timeline;
class Stack;
class Track;
class Clip;
class Gap;
class Warp;
class Transition;
class ComposableRef;
class Topology;
class ProjectionOperator;
class TemporalProjectionBuilder;

// ============================================================================
// Media Reference
// ============================================================================

/// Information about media being referenced by a Clip
struct MediaReference {
    MediaDataType data_type;
    std::string target_uri;  // For Uri type
    Domain domain;
    std::optional<ContinuousInterval> bounds;
    std::optional<SampleIndexGenerator> discrete_info;

    // Queries
    bool is_uri() const { return data_type == MediaDataType::Uri; }
    bool is_signal() const { return data_type == MediaDataType::Signal; }
    bool is_null() const { return data_type == MediaDataType::Null; }
};

// ============================================================================
// ComposableRef - Non-owning reference to any composable object
// ============================================================================

class ComposableRef {
public:
    // Forward declare ChildIterator - defined after ComposableRef
    class ChildIterator;

    // Construction
    ComposableRef() : handle_{otio_ct_err, nullptr} {}
    explicit ComposableRef(otio_CompositionItemHandle h) : handle_(h) {}

    // Type query
    ComposableType type() const {
        switch (handle_.kind) {
            case otio_ct_timeline:   return ComposableType::Timeline;
            case otio_ct_stack:      return ComposableType::Stack;
            case otio_ct_track:      return ComposableType::Track;
            case otio_ct_clip:       return ComposableType::Clip;
            case otio_ct_gap:        return ComposableType::Gap;
            case otio_ct_warp:       return ComposableType::Warp;
            case otio_ct_transition: return ComposableType::Transition;
            default:                 return ComposableType::Error;
        }
    }

    bool valid() const { return handle_.ref != nullptr; }

    // Name access
    std::optional<std::string> name() const {
        if (!valid()) return std::nullopt;
        char buf[256];
        if (otio_fetch_cvr_name_str(handle_, buf, sizeof(buf)) == 0) {
            std::string result(buf);
            if (result.empty() || result == "null") return std::nullopt;
            return result;
        }
        return std::nullopt;
    }

    // Type name
    std::string type_name() const {
        char buf[64];
        if (otio_fetch_cvr_type_str(handle_, buf, sizeof(buf)) == 0) {
            return std::string(buf);
        }
        return "unknown";
    }

    // Child access
    size_t child_count() const {
        if (!valid()) return 0;
        int count = otio_child_count_cvr(handle_);
        return count >= 0 ? static_cast<size_t>(count) : 0;
    }

    ComposableRef child_at(size_t index) const {
        if (!valid()) return ComposableRef();
        return ComposableRef(otio_fetch_child_cvr_ind(handle_, static_cast<int>(index)));
    }

    // Bounds access
    std::optional<ContinuousInterval> bounds() const {
        if (!valid()) return std::nullopt;
        otio_ContinuousInterval result;
        if (otio_composable_bounds(handle_, &result) == 0) {
            return ContinuousInterval(result);
        }
        return std::nullopt;
    }

    // Iteration support (defined after ChildIterator)
    ChildIterator begin() const;
    ChildIterator end() const;

    // Type-safe downcasting (implemented after class definitions)
    const Clip* as_clip() const;
    const Gap* as_gap() const;
    const Track* as_track() const;
    const Stack* as_stack() const;
    const Warp* as_warp() const;
    const Transition* as_transition() const;
    const Timeline* as_timeline() const;

    // Raw handle access for C API interop
    otio_CompositionItemHandle raw_handle() const { return handle_; }

private:
    otio_CompositionItemHandle handle_;
};

// ChildIterator implementation (must come after ComposableRef is complete)
class ComposableRef::ChildIterator {
public:
    using iterator_category = std::forward_iterator_tag;
    using value_type = ComposableRef;
    using difference_type = std::ptrdiff_t;
    using pointer = const ComposableRef*;
    using reference = ComposableRef;

    ChildIterator() : parent_{}, index_(0), count_(0) {}
    ChildIterator(ComposableRef parent, size_t index)
        : parent_(parent), index_(index), count_(parent.child_count()) {}

    reference operator*() const { return parent_.child_at(index_); }

    ChildIterator& operator++() { ++index_; return *this; }
    ChildIterator operator++(int) { auto tmp = *this; ++(*this); return tmp; }

    bool operator==(const ChildIterator& other) const {
        return index_ == other.index_;
    }
    bool operator!=(const ChildIterator& other) const {
        return !(*this == other);
    }

private:
    ComposableRef parent_;
    size_t index_;
    size_t count_;
};

// Inline definitions for ComposableRef iteration methods
inline ComposableRef::ChildIterator ComposableRef::begin() const {
    return ChildIterator(*this, 0);
}

inline ComposableRef::ChildIterator ComposableRef::end() const {
    return ChildIterator(*this, child_count());
}

// ============================================================================
// Schema Wrapper Classes
// ============================================================================

/// Stack - A container where children are simultaneous in time
class Stack {
public:
    // Properties
    std::optional<std::string> name() const { return ref_.name(); }
    std::optional<ContinuousInterval> bounds() const { return ref_.bounds(); }

    // Children
    size_t child_count() const { return ref_.child_count(); }
    ComposableRef child_at(size_t index) const { return ref_.child_at(index); }

    // Range-based iteration
    ComposableRef::ChildIterator begin() const { return ref_.begin(); }
    ComposableRef::ChildIterator end() const { return ref_.end(); }

    // Generic reference
    ComposableRef ref() const { return ref_; }

private:
    friend class Timeline;
    friend class ComposableRef;
    explicit Stack(otio_CompositionItemHandle h) : ref_(h) {}

    ComposableRef ref_;
};

/// Track - A container where children are sequential in time
class Track {
public:
    // Properties
    std::optional<std::string> name() const { return ref_.name(); }
    std::optional<ContinuousInterval> bounds() const { return ref_.bounds(); }

    // Children
    size_t child_count() const { return ref_.child_count(); }
    ComposableRef child_at(size_t index) const { return ref_.child_at(index); }

    // Range-based iteration
    ComposableRef::ChildIterator begin() const { return ref_.begin(); }
    ComposableRef::ChildIterator end() const { return ref_.end(); }

    // Generic reference
    ComposableRef ref() const { return ref_; }

private:
    friend class ComposableRef;
    explicit Track(otio_CompositionItemHandle h) : ref_(h) {}

    ComposableRef ref_;
};

/// Clip - References a piece of media
class Clip {
public:
    // Properties
    std::optional<std::string> name() const { return ref_.name(); }
    std::optional<ContinuousInterval> bounds() const { return ref_.bounds(); }

    // Media reference access
    MediaReference media() const {
        MediaReference result;
        result.data_type = MediaDataType::Null;
        result.domain = Domain::Time;

        otio_MediaReference media_ref;
        if (otio_clip_media(ref_.raw_handle(), &media_ref) == 0) {
            switch (media_ref.data_type) {
                case otio_mdt_uri:
                    result.data_type = MediaDataType::Uri;
                    if (media_ref.target_uri) {
                        result.target_uri = media_ref.target_uri;
                    }
                    break;
                case otio_mdt_signal:
                    result.data_type = MediaDataType::Signal;
                    break;
                default:
                    result.data_type = MediaDataType::Null;
                    break;
            }

            switch (media_ref.domain) {
                case otio_dm_time:     result.domain = Domain::Time; break;
                case otio_dm_picture:  result.domain = Domain::Picture; break;
                case otio_dm_audio:    result.domain = Domain::Audio; break;
                case otio_dm_metadata: result.domain = Domain::Metadata; break;
                default:               result.domain = Domain::Other; break;
            }

            if (media_ref.has_bounds) {
                result.bounds = ContinuousInterval(media_ref.bounds);
            }

            if (media_ref.has_discrete_info) {
                result.discrete_info = SampleIndexGenerator(media_ref.discrete_info);
            }
        }

        return result;
    }

    // Discrete info for media space
    std::optional<SampleIndexGenerator> discrete_partition() const {
        otio_DiscreteDatasourceIndexGenerator result;
        if (otio_fetch_discrete_info(ref_.raw_handle(), otio_sl_media,
                                     otio_dm_picture, &result) == 0) {
            return SampleIndexGenerator(result);
        }
        return std::nullopt;
    }

    // Generic reference
    ComposableRef ref() const { return ref_; }

private:
    friend class ComposableRef;
    explicit Clip(otio_CompositionItemHandle h) : ref_(h) {}

    ComposableRef ref_;
};

/// Gap - A duration with no media
class Gap {
public:
    // Properties
    std::optional<std::string> name() const { return ref_.name(); }
    std::optional<ContinuousInterval> bounds() const { return ref_.bounds(); }

    // Generic reference
    ComposableRef ref() const { return ref_; }

private:
    friend class ComposableRef;
    explicit Gap(otio_CompositionItemHandle h) : ref_(h) {}

    ComposableRef ref_;
};

/// Warp - A temporal transformation applied to a child
class Warp {
public:
    // Properties
    std::optional<std::string> name() const { return ref_.name(); }

    // The child being warped
    ComposableRef child() const {
        return ComposableRef(otio_warp_child(ref_.raw_handle()));
    }

    // Generic reference
    ComposableRef ref() const { return ref_; }

private:
    friend class ComposableRef;
    explicit Warp(otio_CompositionItemHandle h) : ref_(h) {}

    ComposableRef ref_;
};

/// Transition - A transition between objects in a container
class Transition {
public:
    // Properties
    std::optional<std::string> name() const { return ref_.name(); }

    std::string kind() const {
        char buf[256];
        if (otio_transition_kind(ref_.raw_handle(), buf, sizeof(buf)) >= 0) {
            return std::string(buf);
        }
        return "SMPTE_Dissolve";
    }

    std::optional<ContinuousInterval> bounds() const { return ref_.bounds(); }

    // Generic reference
    ComposableRef ref() const { return ref_; }

private:
    friend class ComposableRef;
    explicit Transition(otio_CompositionItemHandle h) : ref_(h) {}

    ComposableRef ref_;
};

// ============================================================================
// Timeline Class - Root object owning the timeline data
// ============================================================================

class Timeline {
public:
    // Construction
    Timeline() = default;
    ~Timeline();

    // Move-only (owns the underlying data)
    Timeline(Timeline&& other) noexcept;
    Timeline& operator=(Timeline&& other) noexcept;
    Timeline(const Timeline&) = delete;
    Timeline& operator=(const Timeline&) = delete;

    // Properties
    std::optional<std::string> name() const;

    // Access to tracks stack
    Stack tracks() const;

    // Child access (shortcut to tracks().children())
    size_t track_count() const;
    ComposableRef track_at(size_t index) const;

    // Range-based iteration over tracks
    class TrackIterator {
    public:
        using iterator_category = std::forward_iterator_tag;
        using value_type = ComposableRef;
        using difference_type = std::ptrdiff_t;
        using pointer = const ComposableRef*;
        using reference = ComposableRef;

        TrackIterator() : timeline_(nullptr), index_(0) {}
        TrackIterator(const Timeline* tl, size_t index) : timeline_(tl), index_(index) {}

        reference operator*() const { return timeline_->track_at(index_); }
        TrackIterator& operator++() { ++index_; return *this; }
        TrackIterator operator++(int) { auto tmp = *this; ++(*this); return tmp; }

        bool operator==(const TrackIterator& other) const { return index_ == other.index_; }
        bool operator!=(const TrackIterator& other) const { return !(*this == other); }

    private:
        const Timeline* timeline_;
        size_t index_;
    };

    TrackIterator begin() const { return TrackIterator(this, 0); }
    TrackIterator end() const { return TrackIterator(this, track_count()); }

    // Get as generic reference
    ComposableRef ref() const;

    // Validity
    bool valid() const { return handle_.ref != nullptr; }
    explicit operator bool() const { return valid(); }

    // Raw handle access
    otio_CompositionItemHandle raw_handle() const { return handle_; }

private:
    friend Timeline read_from_file(const std::string& path);
    explicit Timeline(otio_CompositionItemHandle h, otio_Arena arena);

    otio_CompositionItemHandle handle_{otio_ct_err, nullptr};
    otio_Arena arena_{nullptr, {nullptr}};
};

// ============================================================================
// Topology and Projection Classes
// ============================================================================

/// Wraps the topology transformation system
class Topology {
public:
    Topology() : handle_{nullptr} {}
    explicit Topology(otio_Topology h) : handle_(h) {}

    // Properties
    std::optional<ContinuousInterval> input_bounds() const {
        if (!valid()) return std::nullopt;
        otio_ContinuousInterval result;
        if (otio_topo_fetch_input_bounds(handle_, &result) == 0) {
            return ContinuousInterval(result);
        }
        return std::nullopt;
    }

    std::optional<ContinuousInterval> output_bounds() const {
        if (!valid()) return std::nullopt;
        otio_ContinuousInterval result;
        if (otio_topo_fetch_output_bounds(handle_, &result) == 0) {
            return ContinuousInterval(result);
        }
        return std::nullopt;
    }

    // Validity
    bool valid() const { return handle_.ref != nullptr; }

    // Raw handle
    otio_Topology raw_handle() const { return handle_; }

private:
    otio_Topology handle_;
};

/// For projecting between temporal spaces
class ProjectionOperator {
public:
    ProjectionOperator() : handle_{nullptr} {}
    explicit ProjectionOperator(otio_ProjectionOperator h) : handle_(h) {}

    // Source and destination
    ComposableRef source() const {
        return ComposableRef(otio_po_fetch_source(handle_));
    }

    ComposableRef destination() const {
        return ComposableRef(otio_po_fetch_destination(handle_));
    }

    // The underlying topology
    Topology topology() const {
        otio_Topology result;
        if (otio_po_fetch_topology(handle_, &result) == 0) {
            return Topology(result);
        }
        return Topology();
    }

    // Continuous projections
    std::optional<Ordinate> project_cc(Ordinate source_ordinate) const {
        double output;
        if (otio_po_project_ordinate_cc(handle_, source_ordinate.as_double(), &output) == 0) {
            return Ordinate(static_cast<float>(output));
        }
        return std::nullopt;
    }

    // Validity
    bool valid() const { return handle_.ref != nullptr; }

    // Raw handle
    otio_ProjectionOperator raw_handle() const { return handle_; }

private:
    otio_ProjectionOperator handle_;
};

/// Builds projection operators for a timeline
class TemporalProjectionBuilder {
public:
    // Construction from a timeline
    explicit TemporalProjectionBuilder(const Timeline& timeline);
    ~TemporalProjectionBuilder();

    // Move-only
    TemporalProjectionBuilder(TemporalProjectionBuilder&& other) noexcept;
    TemporalProjectionBuilder& operator=(TemporalProjectionBuilder&& other) noexcept;
    TemporalProjectionBuilder(const TemporalProjectionBuilder&) = delete;
    TemporalProjectionBuilder& operator=(const TemporalProjectionBuilder&) = delete;

    // Query the projection map
    size_t segment_count() const;
    ContinuousInterval segment_bounds(size_t index) const;

    // Get all segment endpoints
    std::vector<Ordinate> endpoints() const;

    // Get operators for a segment
    size_t operator_count(size_t segment_index) const;
    ProjectionOperator operator_at(size_t segment_index, size_t op_index) const;

    // Validity
    bool valid() const { return handle_.ref != nullptr; }

private:
    otio_ProjectionTopology handle_{nullptr};
    otio_Arena arena_{nullptr, {nullptr}};
};

// ============================================================================
// File I/O
// ============================================================================

/// Read a timeline from file - auto-detects format from extension
Timeline read_from_file(const std::string& path);

// ============================================================================
// ComposableRef Downcasting Implementation
// ============================================================================

inline const Clip* ComposableRef::as_clip() const {
    if (type() != ComposableType::Clip) return nullptr;
    static thread_local Clip clip(handle_);
    clip = Clip(handle_);
    return &clip;
}

inline const Gap* ComposableRef::as_gap() const {
    if (type() != ComposableType::Gap) return nullptr;
    static thread_local Gap gap(handle_);
    gap = Gap(handle_);
    return &gap;
}

inline const Track* ComposableRef::as_track() const {
    if (type() != ComposableType::Track) return nullptr;
    static thread_local Track track(handle_);
    track = Track(handle_);
    return &track;
}

inline const Stack* ComposableRef::as_stack() const {
    if (type() != ComposableType::Stack) return nullptr;
    static thread_local Stack stack(handle_);
    stack = Stack(handle_);
    return &stack;
}

inline const Warp* ComposableRef::as_warp() const {
    if (type() != ComposableType::Warp) return nullptr;
    static thread_local Warp warp(handle_);
    warp = Warp(handle_);
    return &warp;
}

inline const Transition* ComposableRef::as_transition() const {
    if (type() != ComposableType::Transition) return nullptr;
    static thread_local Transition transition(handle_);
    transition = Transition(handle_);
    return &transition;
}

inline const Timeline* ComposableRef::as_timeline() const {
    // Timeline is an owning type, can't safely cast
    return nullptr;
}

} // namespace otio

#endif // OPENTIMELINEIO_HPP

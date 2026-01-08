// opentimelineio.cpp - C++ API Implementation
//
// Implementation of the C++ wrapper classes for OpenTimelineIO/Wrinkles.

#include "opentimelineio.hpp"

namespace otio {

// ============================================================================
// Timeline Implementation
// ============================================================================

Timeline::Timeline(otio_CompositionItemHandle h, otio_Arena arena)
    : handle_(h), arena_(arena) {}

Timeline::~Timeline() {
    if (handle_.ref) {
        otio_timeline_deinit(handle_);
    }
    if (arena_.arena) {
        otio_arena_deinit(arena_);
    }
}

Timeline::Timeline(Timeline&& other) noexcept
    : handle_(other.handle_), arena_(other.arena_) {
    other.handle_ = {otio_ct_err, nullptr};
    other.arena_ = {nullptr, {nullptr}};
}

Timeline& Timeline::operator=(Timeline&& other) noexcept {
    if (this != &other) {
        // Clean up current
        if (handle_.ref) {
            otio_timeline_deinit(handle_);
        }
        if (arena_.arena) {
            otio_arena_deinit(arena_);
        }
        // Take ownership
        handle_ = other.handle_;
        arena_ = other.arena_;
        other.handle_ = {otio_ct_err, nullptr};
        other.arena_ = {nullptr, {nullptr}};
    }
    return *this;
}

std::optional<std::string> Timeline::name() const {
    if (!valid()) return std::nullopt;
    char buf[256];
    if (otio_fetch_cvr_name_str(handle_, buf, sizeof(buf)) == 0) {
        std::string result(buf);
        if (result.empty() || result == "null") return std::nullopt;
        return result;
    }
    return std::nullopt;
}

Stack Timeline::tracks() const {
    // Timeline's child is always a Stack containing tracks
    otio_CompositionItemHandle stack_handle = otio_fetch_child_cvr_ind(handle_, 0);
    // Actually for timeline, children are tracks directly accessed
    return Stack(handle_);
}

size_t Timeline::track_count() const {
    if (!valid()) return 0;
    int count = otio_child_count_cvr(handle_);
    return count >= 0 ? static_cast<size_t>(count) : 0;
}

ComposableRef Timeline::track_at(size_t index) const {
    if (!valid()) return ComposableRef();
    return ComposableRef(otio_fetch_child_cvr_ind(handle_, static_cast<int>(index)));
}

ComposableRef Timeline::ref() const {
    return ComposableRef(handle_);
}

// ============================================================================
// TemporalProjectionBuilder Implementation
// ============================================================================

TemporalProjectionBuilder::TemporalProjectionBuilder(const Timeline& timeline) {
    arena_ = otio_fetch_allocator_new_arena();
    handle_ = otio_build_projection_op_map_to_media_tp_cvr(
        arena_.allocator,
        timeline.raw_handle()
    );
}

TemporalProjectionBuilder::~TemporalProjectionBuilder() {
    // The projection topology is allocated via the arena, so just clean up arena
    if (arena_.arena) {
        otio_arena_deinit(arena_);
    }
}

TemporalProjectionBuilder::TemporalProjectionBuilder(TemporalProjectionBuilder&& other) noexcept
    : handle_(other.handle_), arena_(other.arena_) {
    other.handle_ = {nullptr};
    other.arena_ = {nullptr, {nullptr}};
}

TemporalProjectionBuilder& TemporalProjectionBuilder::operator=(TemporalProjectionBuilder&& other) noexcept {
    if (this != &other) {
        if (arena_.arena) {
            otio_arena_deinit(arena_);
        }
        handle_ = other.handle_;
        arena_ = other.arena_;
        other.handle_ = {nullptr};
        other.arena_ = {nullptr, {nullptr}};
    }
    return *this;
}

size_t TemporalProjectionBuilder::segment_count() const {
    if (!valid()) return 0;
    return otio_po_map_fetch_num_segments(handle_);
}

ContinuousInterval TemporalProjectionBuilder::segment_bounds(size_t index) const {
    if (!valid()) return ContinuousInterval();
    otio_ContinuousInterval result;
    if (otio_po_map_fetch_segment_bounds(handle_, index, &result) == 0) {
        return ContinuousInterval(result);
    }
    return ContinuousInterval();
}

std::vector<Ordinate> TemporalProjectionBuilder::endpoints() const {
    std::vector<Ordinate> result;
    if (!valid()) return result;

    size_t count = otio_po_map_fetch_num_endpoints(handle_);
    const float* endpoints = reinterpret_cast<const float*>(
        otio_po_map_fetch_endpoints(handle_)
    );

    result.reserve(count * 2);  // start and end for each segment
    for (size_t i = 0; i < count; ++i) {
        // Each endpoint is a ContinuousInterval, so we get start/end pairs
        result.push_back(Ordinate(endpoints[i * 2]));
        result.push_back(Ordinate(endpoints[i * 2 + 1]));
    }

    return result;
}

size_t TemporalProjectionBuilder::operator_count(size_t segment_index) const {
    if (!valid()) return 0;
    return otio_po_map_fetch_num_operators_for_segment(handle_, segment_index);
}

ProjectionOperator TemporalProjectionBuilder::operator_at(size_t segment_index, size_t op_index) const {
    if (!valid()) return ProjectionOperator();

    otio_ProjectionOperator result;
    if (otio_po_map_fetch_op(arena_.allocator, handle_, segment_index, op_index, &result) == 0) {
        return ProjectionOperator(result);
    }
    return ProjectionOperator();
}

// ============================================================================
// File I/O Implementation
// ============================================================================

Timeline read_from_file(const std::string& path) {
    // Create arena for this timeline
    otio_Arena arena = otio_fetch_allocator_new_arena();

    // Call C API
    otio_CompositionItemHandle handle = otio_read_from_file(
        arena.allocator,
        path.c_str()
    );

    // Check for errors
    if (handle.kind == otio_ct_err || handle.ref == nullptr) {
        otio_arena_deinit(arena);
        throw FileNotFoundError(path);
    }

    if (handle.kind != otio_ct_timeline) {
        otio_arena_deinit(arena);
        throw ParseError("Root object is not a Timeline");
    }

    return Timeline(handle, arena);
}

} // namespace otio

"""Tests for wrinkles schema types."""

import pytest
import wrinkles


class TestReadTimeline:
    """Tests for reading timeline files."""

    def test_read_otio_file(self, multiple_track_otio):
        """Test reading an OTIO file."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        assert tl is not None
        assert isinstance(tl, wrinkles.Timeline)

    def test_timeline_has_name(self, multiple_track_otio):
        """Test that timeline has a name."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        assert tl.name is not None
        assert "Multiple Tracks" in tl.name

    def test_timeline_has_tracks(self, multiple_track_otio):
        """Test that timeline has tracks."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        tracks = tl.tracks
        assert tracks is not None
        # In wrinkles, tracks property returns the Timeline itself (which is iterable)
        assert isinstance(tracks, wrinkles.Timeline)
        assert len(tracks) > 0

    def test_invalid_file_raises(self):
        """Test that reading a non-existent file raises an error."""
        with pytest.raises(IOError):
            wrinkles.read_from_file("/nonexistent/file.otio")


class TestHierarchyTraversal:
    """Tests for traversing the timeline hierarchy."""

    def test_iterate_tracks(self, multiple_track_otio):
        """Test iterating over tracks."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        tracks_list = list(tl.tracks)
        assert len(tracks_list) >= 1
        for track in tracks_list:
            assert isinstance(track, wrinkles.Track)

    def test_iterate_track_children(self, multiple_track_otio):
        """Test iterating over track children."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        first_track = tl.tracks[0]
        children = list(first_track)
        assert len(children) > 0
        for child in children:
            assert isinstance(child, (wrinkles.Clip, wrinkles.Gap, wrinkles.Warp, wrinkles.Transition))

    def test_index_access(self, multiple_track_otio):
        """Test index-based access to children."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        tracks = tl.tracks
        assert tracks[0] is not None
        assert isinstance(tracks[0], wrinkles.Track)

    def test_index_out_of_bounds(self, multiple_track_otio):
        """Test that out-of-bounds index raises IndexError."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        tracks = tl.tracks
        with pytest.raises(IndexError):
            _ = tracks[9999]

    def test_len_function(self, multiple_track_otio):
        """Test len() on containers."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        tracks = tl.tracks
        length = len(tracks)
        assert length > 0
        assert length == 3  # multiple_track.otio has 3 tracks


class TestItemProperties:
    """Tests for composition item properties."""

    def test_clip_name(self, multiple_track_otio):
        """Test clip name property."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        first_track = tl.tracks[0]
        first_clip = first_track[0]
        assert isinstance(first_clip, wrinkles.Clip)
        assert first_clip.name is not None

    def test_type_name(self, multiple_track_otio):
        """Test type_name property."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        assert tl.type_name == "timeline"
        # In wrinkles, tl.tracks returns Timeline, not Stack
        assert tl.tracks.type_name == "timeline"
        assert tl.tracks[0].type_name == "track"


class TestContextManager:
    """Tests for context manager support."""

    def test_with_statement(self, multiple_track_otio):
        """Test using timeline with context manager."""
        with wrinkles.read_from_file(multiple_track_otio) as tl:
            assert tl.name is not None
            tracks = list(tl.tracks)
            assert len(tracks) > 0


class TestContinuousInterval:
    """Tests for ContinuousInterval type."""

    def test_create_interval(self):
        """Test creating a continuous interval."""
        interval = wrinkles.ContinuousInterval(1.0, 5.0)
        assert interval.start == 1.0
        assert interval.end == 5.0

    def test_interval_duration(self):
        """Test interval duration property."""
        interval = wrinkles.ContinuousInterval(1.0, 5.0)
        assert interval.duration == 4.0

    def test_interval_repr(self):
        """Test interval string representation."""
        interval = wrinkles.ContinuousInterval(1.0, 5.0)
        repr_str = repr(interval)
        assert "ContinuousInterval" in repr_str
        assert "1.0" in repr_str
        assert "5.0" in repr_str


class TestProjection:
    """Tests for projection operators."""

    def test_build_projection_map(self, multiple_track_otio):
        """Test building a projection map."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        projections = wrinkles.build_projection_map(tl)
        assert projections is not None
        assert len(projections) > 0

    def test_projection_operator_project_cc(self, multiple_track_otio):
        """Test continuous-to-continuous projection."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        projections = wrinkles.build_projection_map(tl)
        if projections:
            proj = projections[0]
            result = proj.project_cc(0.0)
            # Result may be None if out of bounds, or a float
            assert result is None or isinstance(result, float)

    def test_projection_operator_source_destination(self, multiple_track_otio):
        """Test source and destination properties."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        projections = wrinkles.build_projection_map(tl)
        if projections:
            proj = projections[0]
            # Source should be the timeline
            source = proj.source
            assert source is not None
            # Destination should be a clip
            dest = proj.destination
            assert dest is not None

"""Tests for wrinkles schema types."""

import os
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


class TestWriteTimeline:
    """Tests for writing timeline files."""

    def test_write_tla_format(self, multiple_track_otio, tmp_path):
        """Test writing a timeline to TLA (ASCII) format."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        output_path = str(tmp_path / "output.tla")
        wrinkles.write_to_file(tl, output_path)
        assert os.path.exists(output_path)
        # Verify file has content
        with open(output_path, 'r') as f:
            content = f.read()
        assert len(content) > 0
        # TLA format includes schema_version and track definitions
        assert ".schema_version" in content
        assert "track" in content.lower()

    def test_write_tlb_format(self, multiple_track_otio, tmp_path):
        """Test writing a timeline to TLB (binary) format."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        output_path = str(tmp_path / "output.tlb")
        wrinkles.write_to_file(tl, output_path)
        assert os.path.exists(output_path)
        # Verify file has content
        file_size = os.path.getsize(output_path)
        assert file_size > 0

    def test_write_tlfb_format(self, multiple_track_otio, tmp_path):
        """Test writing a timeline to TLFB (FlatBuffers) format."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        output_path = str(tmp_path / "output.tlfb")
        wrinkles.write_to_file(tl, output_path)
        assert os.path.exists(output_path)
        # Verify file has content
        file_size = os.path.getsize(output_path)
        assert file_size > 0

    def test_roundtrip_tla(self, multiple_track_otio, tmp_path):
        """Test round-trip: read OTIO -> write TLA -> read TLA."""
        # Read original
        tl1 = wrinkles.read_from_file(multiple_track_otio)
        original_name = tl1.name
        original_track_count = len(list(tl1.tracks))

        # Write to TLA
        output_path = str(tmp_path / "roundtrip.tla")
        wrinkles.write_to_file(tl1, output_path)

        # Read back
        tl2 = wrinkles.read_from_file(output_path)
        assert tl2.name == original_name
        assert len(list(tl2.tracks)) == original_track_count

    def test_roundtrip_tlb(self, multiple_track_otio, tmp_path):
        """Test round-trip: read OTIO -> write TLB -> read TLB."""
        # Read original
        tl1 = wrinkles.read_from_file(multiple_track_otio)
        original_name = tl1.name
        original_track_count = len(list(tl1.tracks))

        # Write to TLB
        output_path = str(tmp_path / "roundtrip.tlb")
        wrinkles.write_to_file(tl1, output_path)

        # Read back
        tl2 = wrinkles.read_from_file(output_path)
        assert tl2.name == original_name
        assert len(list(tl2.tracks)) == original_track_count

    def test_roundtrip_preserves_clip_names(self, multiple_track_otio, tmp_path):
        """Test that round-trip preserves clip names."""
        # Read original and get clip names
        tl1 = wrinkles.read_from_file(multiple_track_otio)
        original_clips = []
        for track in tl1.tracks:
            for item in track:
                if isinstance(item, wrinkles.Clip) and item.name:
                    original_clips.append(item.name)

        # Write and read back
        output_path = str(tmp_path / "clips_test.tla")
        wrinkles.write_to_file(tl1, output_path)
        tl2 = wrinkles.read_from_file(output_path)

        # Verify clip names preserved
        roundtrip_clips = []
        for track in tl2.tracks:
            for item in track:
                if isinstance(item, wrinkles.Clip) and item.name:
                    roundtrip_clips.append(item.name)

        assert len(roundtrip_clips) == len(original_clips)
        for orig, rt in zip(original_clips, roundtrip_clips):
            assert orig == rt

    def test_write_requires_timeline(self, multiple_track_otio, tmp_path):
        """Test that write_to_file requires a Timeline object."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        track = tl.tracks[0]  # Get a track (not a timeline)

        with pytest.raises(TypeError):
            wrinkles.write_to_file(track, str(tmp_path / "output.tla"))

    def test_write_invalid_extension(self, multiple_track_otio, tmp_path):
        """Test that unsupported file extension raises error."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        with pytest.raises(IOError):
            wrinkles.write_to_file(tl, str(tmp_path / "output.xyz"))

    def test_write_otio_format_fails(self, multiple_track_otio, tmp_path):
        """Test that writing to .otio format fails (read-only format)."""
        tl = wrinkles.read_from_file(multiple_track_otio)
        with pytest.raises(IOError):
            wrinkles.write_to_file(tl, str(tmp_path / "output.otio"))

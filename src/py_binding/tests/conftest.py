"""Pytest configuration and fixtures for wrinkles tests."""

import os
import pytest

# Get the path to sample OTIO files
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SAMPLE_FILES_DIR = os.path.join(PROJECT_ROOT, "sample_otio_files")


@pytest.fixture
def sample_otio_dir():
    """Return the path to sample OTIO files directory."""
    return SAMPLE_FILES_DIR


@pytest.fixture
def multiple_track_otio():
    """Return the path to the multiple_track.otio test file."""
    return os.path.join(SAMPLE_FILES_DIR, "multiple_track.otio")


@pytest.fixture
def simple_cut_otio():
    """Return the path to the simple_cut.otio test file."""
    return os.path.join(SAMPLE_FILES_DIR, "simple_cut.otio")

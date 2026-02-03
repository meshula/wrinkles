"""Setup script for wrinkles Python bindings."""

import os
import sys
from setuptools import setup, Extension

# Get the directory containing this setup.py
here = os.path.dirname(os.path.abspath(__file__))

# Path to the wrinkles project root (three levels up from language_bindings/python)
project_root = os.path.dirname(os.path.dirname(os.path.dirname(here)))

# Include directories for C headers
include_dirs = [
    os.path.join(project_root, "src", "language_bindings", "c"),
]

# Library directories
library_dirs = [
    os.path.join(project_root, "zig-out", "lib"),
]

# Platform-specific settings
extra_compile_args = ["-std=c11"]
extra_link_args = []

# Use static library for relocatable builds (no rpath needed)
# The static library bundles compiler-rt for soft-float symbols like __divtf3
libraries = ["opentimelineio_c_static"]

if sys.platform == "darwin":
    # macOS: link against libc++ for C++ standard library support
    libraries.append("c++")
elif sys.platform.startswith("linux"):
    # Linux: link against libstdc++
    libraries.append("stdc++")

wrinkles_ext = Extension(
    "wrinkles._wrinkles",
    sources=["wrinkles/_wrinkles.c"],
    include_dirs=include_dirs,
    library_dirs=library_dirs,
    libraries=libraries,
    extra_compile_args=extra_compile_args,
    extra_link_args=extra_link_args,
)

setup(
    ext_modules=[wrinkles_ext],
)

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

if sys.platform == "darwin":
    # macOS: set rpath to find the library
    extra_link_args.extend([
        "-Wl,-rpath,@loader_path/../../../../zig-out/lib",
        f"-Wl,-rpath,{os.path.join(project_root, 'zig-out', 'lib')}",
    ])
elif sys.platform.startswith("linux"):
    extra_link_args.extend([
        f"-Wl,-rpath,{os.path.join(project_root, 'zig-out', 'lib')}",
    ])

# Define the C extension module
libraries = ["opentimelineio_c"]

# Add compiler-rt for ARM64 macOS
if sys.platform == "darwin":
    libraries.append("c++")

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

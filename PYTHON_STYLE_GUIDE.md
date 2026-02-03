# Python Style Guide

This style guide is based on the Python code conventions used in the OpenTimelineIO project.

## File Headers

All Python files should include an SPDX license identifier and copyright notice:

```python
# SPDX-License-Identifier: Apache-2.0
# Copyright Contributors to the wrinkles project
```

## Imports

Organize imports in the following order, separated by blank lines:

1. Standard library imports
2. Third-party library imports
3. Local application imports

Within each group, imports should be alphabetically sorted.

```python
# Standard library
import json
import sys
from typing import Any, Dict, List, Optional

# Third-party (if applicable)
import opentimelineio as otio

# Local
from wrinkles import serialization
```

## Naming Conventions

- **Modules**: lowercase with underscores (e.g., `otio_to_ziggy.py`)
- **Classes**: PascalCase (e.g., `RationalTime`, `TimeRange`)
- **Functions/Methods**: snake_case (e.g., `convert_clip`, `rational_time_to_float`)
- **Constants**: UPPER_CASE_WITH_UNDERSCORES (e.g., `DEFAULT_RATE`)
- **Private functions/methods**: prefix with single underscore (e.g., `_internal_helper`)

## Code Formatting

- **Indentation**: 4 spaces (no tabs)
- **Line length**: Aim for 79-88 characters, but can extend to 100 for readability
- **Blank lines**:
  - Two blank lines between top-level functions and classes
  - One blank line between methods within a class
- **Quotes**: Use double quotes for strings by default
- **Trailing commas**: Use trailing commas in multi-line data structures

```python
# Good
data = {
    "name": "example",
    "value": 42,
}

# Also good for single-line
data = {"name": "example", "value": 42}
```

## Documentation

### Module Docstrings

Every module should have a docstring explaining its purpose:

```python
#!/usr/bin/env python3
"""
Convert OpenTimelineIO JSON files to Ziggy format.

Usage:
    python otio_to_ziggy.py input.otio output.ziggy
"""
```

### Function Docstrings

Use clear, descriptive docstrings for all public functions:

```python
def rational_time_to_float(rational_time: Dict[str, Any]) -> float:
    """Convert OTIO RationalTime to float seconds.

    Args:
        rational_time: Dictionary with 'value' and 'rate' keys

    Returns:
        Time in seconds as a float

    Raises:
        ValueError: If rational_time is not a valid RationalTime.1 schema
    """
    if rational_time.get("OTIO_SCHEMA") != "RationalTime.1":
        raise ValueError(f"Expected RationalTime.1, got {rational_time.get('OTIO_SCHEMA')}")

    value = rational_time["value"]
    rate = rational_time["rate"]
    return float(value) / float(rate)
```

### Docstring Sections

Use these sections in function docstrings when appropriate:

- **Args**: Parameter descriptions
- **Returns**: Return value description
- **Raises**: Exception descriptions
- **Example**: Usage examples (for complex functions)
- **Note**: Additional important information

## Type Hints

Use type hints for function parameters and return values:

```python
from typing import Any, Dict, List, Optional

def convert_clip(clip: Dict[str, Any]) -> Dict[str, Any]:
    """Convert OTIO Clip to Ziggy format."""
    # implementation

def get_name(obj: Dict[str, Any]) -> Optional[str]:
    """Return name or None if not present."""
    return obj.get("name")
```

## Error Handling

- Use specific exception types rather than bare `except:`
- Include helpful error messages with context
- Validate inputs early

```python
# Good
def process_data(data: Dict[str, Any]) -> Any:
    schema_type = data.get("OTIO_SCHEMA")
    if schema_type != "Clip.1":
        raise ValueError(f"Expected Clip.1, got {schema_type}")
    # process...

# Avoid
def process_data(data):
    try:
        # lots of code
    except:
        pass
```

## Functions

- Keep functions focused on a single task
- Prefer pure functions when possible (no side effects)
- Use helper functions to break down complex logic
- Return early to reduce nesting

```python
# Good
def convert_media_reference(
    media_ref: Dict[str, Any],
    discrete_rate: Optional[int] = None
) -> Dict[str, Any]:
    """Convert OTIO MediaReference to Ziggy format.

    Args:
        media_ref: The OTIO media reference dictionary
        discrete_rate: If provided, use this as the sample rate
    """
    schema_type = media_ref.get("OTIO_SCHEMA")

    if schema_type == "MissingReference.1":
        return _convert_missing_reference(discrete_rate)

    if schema_type == "ExternalReference.1":
        return _convert_external_reference(media_ref, discrete_rate)

    # Default case
    return _convert_default_reference(discrete_rate)
```

## Testing

Tests should use the `unittest` framework:

```python
import unittest

class TestConversion(unittest.TestCase):
    """Test suite for OTIO to Ziggy conversion."""

    def test_rational_time_conversion(self):
        """Test conversion of RationalTime to float."""
        rational_time = {
            "OTIO_SCHEMA": "RationalTime.1",
            "value": 24,
            "rate": 24
        }
        result = rational_time_to_float(rational_time)
        self.assertEqual(result, 1.0)

    def test_invalid_schema_raises_error(self):
        """Test that invalid schema raises ValueError."""
        invalid_time = {"OTIO_SCHEMA": "Invalid.1"}
        with self.assertRaises(ValueError):
            rational_time_to_float(invalid_time)

if __name__ == "__main__":
    unittest.main()
```

## Comments

- Write self-documenting code where possible
- Use comments to explain "why", not "what"
- Keep comments up to date with code changes

```python
# Good
# Convert to discrete indices because we need frame-accurate editing
if discrete_rate is not None:
    start_index = int(start_time["value"])
    end_index = start_index + int(duration["value"])

# Avoid
# Set start_index to the value of start_time
start_index = int(start_time["value"])
```

## Command-Line Scripts

Scripts should:

- Include shebang line: `#!/usr/bin/env python3`
- Have a module docstring with usage information
- Use `if __name__ == "__main__":` guard
- Provide clear usage messages for incorrect arguments
- Use `sys.exit(1)` for error exits

```python
#!/usr/bin/env python3
"""
Script description here.

Usage:
    python script.py <input> <output>
"""

import sys

def main():
    if len(sys.argv) != 3:
        print("Usage: python script.py <input> <output>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    # process...

    print(f"Converted {input_file} to {output_file}")

if __name__ == "__main__":
    main()
```

## Data Structures

- Use dictionaries for structured data
- Use named tuples or dataclasses for complex structures
- Prefer immutable data structures when possible

```python
from typing import NamedTuple

class Bounds(NamedTuple):
    """Represent time bounds."""
    start: float
    end: float

# Usage
bounds = Bounds(start=0.0, end=5.0)
```

## Best Practices

1. **Avoid magic numbers**: Use named constants
2. **Don't repeat yourself (DRY)**: Extract common logic into functions
3. **Fail fast**: Validate inputs early and provide clear error messages
4. **Write testable code**: Keep functions small and focused
5. **Follow PEP 8**: Use a linter like `flake8` or `ruff`

## Tools

Recommended tools for maintaining code quality:

- **Linter**: `flake8` or `ruff`
- **Type checker**: `mypy`
- **Formatter**: `black` (optional, but maintains consistency)
- **Testing**: `unittest` (standard library)

## Example Script Structure

```python
#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright Contributors to the wrinkles project

"""
Brief description of what this script does.

Usage:
    python script.py [options] <input>
"""

import json
import sys
from typing import Any, Dict, Optional


# Constants
DEFAULT_RATE = 24


def process_item(item: Dict[str, Any]) -> Dict[str, Any]:
    """Process a single item.

    Args:
        item: The item to process

    Returns:
        Processed item dictionary
    """
    # Implementation
    pass


def main():
    """Main entry point for the script."""
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    input_file = sys.argv[1]

    # Read input
    with open(input_file, 'r') as f:
        data = json.load(f)

    # Process
    result = process_item(data)

    # Write output
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
```

## References

- [PEP 8 – Style Guide for Python Code](https://peps.python.org/pep-0008/)
- [PEP 257 – Docstring Conventions](https://peps.python.org/pep-0257/)
- [OpenTimelineIO Repository](https://github.com/AcademySoftwareFoundation/OpenTimelineIO)

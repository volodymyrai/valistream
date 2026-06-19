"""NO_COLOR / --no-color handling and colorama initialization."""

from __future__ import annotations

import os
import sys


def should_use_color(no_color_flag: bool) -> bool:
    """Determine whether color output should be enabled."""
    if no_color_flag:
        return False
    if os.environ.get("NO_COLOR") is not None:
        return False
    if not hasattr(sys.stdout, "isatty") or not sys.stdout.isatty():
        return False
    return True


def init_color(enabled: bool) -> None:
    """Initialize colorama for Windows terminal color support."""
    if not enabled:
        return
    try:
        import colorama

        colorama.just_fix_windows_console()
    except ImportError:
        pass

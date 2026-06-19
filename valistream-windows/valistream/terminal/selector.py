"""questionary interactive rendition picker."""

from __future__ import annotations

import sys

import questionary

from valistream.parser.models import Rendition


def _rendition_label(r: Rendition) -> str:
    """Build a human-readable label for a rendition."""
    parts = [r.alias]
    if r.resolution:
        parts.append(r.resolution)
    if r.bandwidth:
        parts.append(f"{r.bandwidth // 1000}k")
    if r.codecs:
        parts.append(r.codecs)
    return " | ".join(parts)


def select_renditions_interactive(renditions: list[Rendition]) -> list[Rendition]:
    """Show an interactive checklist for rendition selection.

    All renditions are pre-checked. Falls back to returning all renditions
    if stdin is not a TTY.
    """
    if not renditions:
        return []

    if not sys.stdin.isatty():
        return list(renditions)

    choices = [
        questionary.Choice(title=_rendition_label(r), value=r, checked=True)
        for r in renditions
    ]

    selected = questionary.checkbox(
        "Select renditions to monitor:",
        choices=choices,
    ).ask()

    if selected is None:
        return list(renditions)

    return selected

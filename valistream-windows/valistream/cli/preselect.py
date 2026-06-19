"""Rendition filter/preselect logic."""

from __future__ import annotations

import re

from valistream.parser.models import Rendition


def filter_renditions(patterns: str, renditions: list[Rendition]) -> list[Rendition]:
    """Filter renditions by comma-separated pattern strings.

    Each pattern is matched case-insensitively against the rendition's URI,
    alias, resolution, codecs, bandwidth, name, group_id, and language.
    A rendition is included if ANY pattern matches ANY of its fields.
    Returns all renditions if no pattern matches anything.
    """
    if not patterns or not patterns.strip():
        return list(renditions)

    parts = [p.strip() for p in patterns.split(",") if p.strip()]
    if not parts:
        return list(renditions)

    compiled = [re.compile(re.escape(p), re.IGNORECASE) for p in parts]

    matched: list[Rendition] = []
    for r in renditions:
        candidates = [
            r.uri,
            r.alias,
            r.resolution or "",
            r.codecs or "",
            str(r.bandwidth),
            r.name or "",
            r.group_id or "",
            r.language or "",
        ]
        if any(pat.search(c) for pat in compiled for c in candidates):
            matched.append(r)

    return matched if matched else list(renditions)

"""URL resolution helpers for HLS playlists."""

from __future__ import annotations

from urllib.parse import urljoin


def resolve_playlist_url(base_url: str, relative_url: str) -> str:
    """Resolve a relative URL against a base playlist URL.

    Handles relative, absolute, and protocol-relative URLs.
    """
    if not relative_url:
        return base_url
    return urljoin(base_url, relative_url)

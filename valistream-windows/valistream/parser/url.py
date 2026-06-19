"""URL resolution helpers for HLS playlists."""

from __future__ import annotations

from urllib.parse import urljoin, urlparse, urlunparse


def resolve_playlist_url(base_url: str, relative_url: str) -> str:
    """Resolve a relative URL against a base playlist URL.

    Handles relative, absolute, and protocol-relative URLs.
    When the relative URL has no query string, the base URL's query string is
    propagated to the resolved URL so CDN auth tokens are not lost.
    """
    if not relative_url:
        return base_url
    resolved = urljoin(base_url, relative_url)
    # Propagate the base URL's query string (CDN tokens, etc.) to the resolved
    # URL, but only when the relative URL is a path reference (not an absolute
    # URL or protocol-relative reference that targets a different origin).
    _is_path_ref = "://" not in relative_url and not relative_url.startswith("//")
    if _is_path_ref and "?" not in relative_url:
        base_query = urlparse(base_url).query
        if base_query and "?" not in resolved:
            resolved = urlunparse(urlparse(resolved)._replace(query=base_query))
    return resolved

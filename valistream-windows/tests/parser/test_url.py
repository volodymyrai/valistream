"""Tests for URL resolution."""

import pytest

from valistream.parser.url import resolve_playlist_url


@pytest.mark.parametrize(
    ("base", "relative", "expected"),
    [
        (
            "http://cdn.example.com/live/master.m3u8",
            "720p.m3u8",
            "http://cdn.example.com/live/720p.m3u8",
        ),
        (
            "http://cdn.example.com/live/master.m3u8",
            "../other/720p.m3u8",
            "http://cdn.example.com/other/720p.m3u8",
        ),
        (
            "http://cdn.example.com/live/master.m3u8",
            "http://other.cdn.com/720p.m3u8",
            "http://other.cdn.com/720p.m3u8",
        ),
        (
            "http://cdn.example.com/live/master.m3u8",
            "//other.cdn.com/720p.m3u8",
            "http://other.cdn.com/720p.m3u8",
        ),
        (
            "https://cdn.example.com/live/master.m3u8",
            "//other.cdn.com/720p.m3u8",
            "https://other.cdn.com/720p.m3u8",
        ),
        (
            "http://cdn.example.com/live/master.m3u8",
            "/absolute/720p.m3u8",
            "http://cdn.example.com/absolute/720p.m3u8",
        ),
        (
            "http://cdn.example.com/live/master.m3u8",
            "",
            "http://cdn.example.com/live/master.m3u8",
        ),
        (
            "http://cdn.example.com/live/sub/master.m3u8",
            "seg0.ts",
            "http://cdn.example.com/live/sub/seg0.ts",
        ),
        (
            "https://cdn.example.com/live/master.m3u8?token=abc&va=123",
            "720p/index.m3u8",
            "https://cdn.example.com/live/720p/index.m3u8?token=abc&va=123",
        ),
        (
            "https://cdn.example.com/live/master.m3u8?token=abc",
            "720p/index.m3u8?token=xyz",
            "https://cdn.example.com/live/720p/index.m3u8?token=xyz",
        ),
        (
            "https://cdn.example.com/live/master.m3u8?token=abc",
            "https://other.cdn.com/720p.m3u8",
            "https://other.cdn.com/720p.m3u8",
        ),
    ],
    ids=[
        "relative-same-dir",
        "relative-parent-dir",
        "absolute-url",
        "protocol-relative-http",
        "protocol-relative-https",
        "absolute-path",
        "empty-returns-base",
        "nested-relative",
        "cdn-token-propagated-to-relative",
        "relative-own-query-not-overridden",
        "absolute-url-not-inheriting-base-query",
    ],
)
def test_resolve_playlist_url(base: str, relative: str, expected: str) -> None:
    assert resolve_playlist_url(base, relative) == expected

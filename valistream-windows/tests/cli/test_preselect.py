"""Tests for rendition preselect/filter logic."""

from __future__ import annotations

from valistream.cli.preselect import filter_renditions
from valistream.parser.models import Rendition


def _make_rendition(
    uri: str = "720p.m3u8",
    bandwidth: int = 1280000,
    resolution: str | None = "1280x720",
    codecs: str | None = None,
    name: str | None = None,
    language: str | None = None,
) -> Rendition:
    return Rendition(
        uri=uri,
        bandwidth=bandwidth,
        resolution=resolution,
        codecs=codecs,
        name=name,
        language=language,
    )


RENDITIONS = [
    _make_rendition(uri="720p.m3u8", bandwidth=1280000, resolution="1280x720"),
    _make_rendition(uri="1080p.m3u8", bandwidth=2560000, resolution="1920x1080"),
    _make_rendition(uri="audio-en.m3u8", bandwidth=128000, resolution=None, language="en"),
]


class TestFilterRenditions:
    def test_empty_pattern_returns_all(self) -> None:
        result = filter_renditions("", RENDITIONS)
        assert len(result) == 3

    def test_none_pattern_returns_all(self) -> None:
        result = filter_renditions("  ", RENDITIONS)
        assert len(result) == 3

    def test_match_by_uri(self) -> None:
        result = filter_renditions("720p", RENDITIONS)
        assert len(result) == 1
        assert result[0].uri == "720p.m3u8"

    def test_match_by_resolution(self) -> None:
        result = filter_renditions("1920x1080", RENDITIONS)
        assert len(result) == 1
        assert result[0].uri == "1080p.m3u8"

    def test_match_by_bandwidth(self) -> None:
        result = filter_renditions("2560000", RENDITIONS)
        assert len(result) == 1
        assert result[0].uri == "1080p.m3u8"

    def test_match_by_language(self) -> None:
        result = filter_renditions("en", RENDITIONS)
        assert len(result) == 1
        assert result[0].language == "en"

    def test_case_insensitive(self) -> None:
        result = filter_renditions("720P", RENDITIONS)
        assert len(result) == 1

    def test_comma_separated_patterns(self) -> None:
        result = filter_renditions("720p, 1080p", RENDITIONS)
        assert len(result) == 2

    def test_no_match_returns_all(self) -> None:
        result = filter_renditions("nonexistent", RENDITIONS)
        assert len(result) == 3

    def test_match_by_alias(self) -> None:
        r = _make_rendition(uri="v.m3u8", resolution="1280x720")
        result = filter_renditions("720p", [r])
        assert len(result) == 1

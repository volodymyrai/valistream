"""Tests for playlist models and alias generation."""

import pytest

from valistream.parser.models import ParseError, Rendition


class TestRenditionAlias:
    @pytest.mark.parametrize(
        ("kwargs", "expected"),
        [
            ({"uri": "720p.m3u8", "bandwidth": 1280000, "resolution": "1280x720"}, "video-720p"),
            ({"uri": "1080p.m3u8", "bandwidth": 2560000, "resolution": "1920x1080"}, "video-1080p"),
            ({"uri": "low.m3u8", "bandwidth": 500000}, "video-500k"),
            (
                {"uri": "en.m3u8", "type": "AUDIO", "language": "en", "name": "English", "group_id": "audio"},
                "audio-en",
            ),
            (
                {"uri": "no.m3u8", "type": "AUDIO", "language": "no", "name": "Norwegian", "group_id": "audio"},
                "audio-no",
            ),
            (
                {"uri": "subs.m3u8", "type": "SUBTITLES", "name": "English", "group_id": "subs"},
                "subtitles-english",
            ),
            (
                {"uri": "cc.m3u8", "type": "CLOSED-CAPTIONS", "group_id": "cc608"},
                "closed-captions-cc608",
            ),
        ],
        ids=[
            "video-720p",
            "video-1080p",
            "video-bandwidth-only",
            "audio-english",
            "audio-norwegian",
            "subtitles-by-name",
            "cc-by-group",
        ],
    )
    def test_alias(self, kwargs: dict, expected: str) -> None:  # type: ignore[type-arg]
        r = Rendition(**kwargs)
        assert r.alias == expected


class TestParseError:
    def test_fields(self) -> None:
        err = ParseError(message="bad format", url="http://example.com/x.m3u8", line_number=5)
        assert err.message == "bad format"
        assert err.url == "http://example.com/x.m3u8"
        assert err.line_number == 5

    def test_optional_line_number(self) -> None:
        err = ParseError(message="oops", url="http://example.com/x.m3u8")
        assert err.line_number is None

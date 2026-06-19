"""Tests for Content-Type validation."""

import pytest

from valistream.validator.content_type import validate_content_type
from valistream.validator.finding import FindingCode, Severity


@pytest.mark.parametrize(
    "ct",
    [
        "application/vnd.apple.mpegurl",
        "application/x-mpegurl",
        "audio/mpegurl",
        "audio/x-mpegurl",
        "application/vnd.apple.mpegurl; charset=utf-8",
        "APPLICATION/VND.APPLE.MPEGURL",
    ],
    ids=[
        "apple-mpegurl",
        "x-mpegurl",
        "audio-mpegurl",
        "audio-x-mpegurl",
        "with-charset",
        "uppercase",
    ],
)
def test_valid_content_types(ct: str) -> None:
    findings = validate_content_type(ct)
    assert len(findings) == 0


@pytest.mark.parametrize(
    "ct",
    [
        "text/plain",
        "application/json",
        "video/mp4",
        "",
    ],
    ids=["text-plain", "json", "video-mp4", "empty"],
)
def test_invalid_content_types(ct: str) -> None:
    findings = validate_content_type(ct, playlist_url="http://example.com/playlist.m3u8")
    assert len(findings) == 1
    assert findings[0].code == FindingCode.DELIVERY_CONTENT_TYPE
    assert findings[0].severity == Severity.WARNING
    assert findings[0].playlist_url == "http://example.com/playlist.m3u8"

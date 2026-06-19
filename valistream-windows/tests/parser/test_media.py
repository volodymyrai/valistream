"""Tests for media playlist parsing."""

from pathlib import Path

from valistream.parser.media import parse_media_playlist
from valistream.parser.models import MediaPlaylist, ParseError

FIXTURES = Path(__file__).parent.parent / "fixtures"
BASE_URL = "http://cdn.example.com/live/720p.m3u8"


def _load(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


class TestMediaPlaylistVOD:
    def test_basic_fields(self) -> None:
        result = parse_media_playlist(_load("media_vod.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.version == 3
        assert result.target_duration == 10.0
        assert result.media_sequence == 0
        assert result.playlist_type == "vod"
        assert result.is_endlist is True

    def test_segment_count(self) -> None:
        result = parse_media_playlist(_load("media_vod.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert len(result.segments) == 3

    def test_segment_durations(self) -> None:
        result = parse_media_playlist(_load("media_vod.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.segments[0].duration == 9.5
        assert result.segments[1].duration == 10.0
        assert result.segments[2].duration == 8.2

    def test_segment_title(self) -> None:
        result = parse_media_playlist(_load("media_vod.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.segments[0].title == "First segment"

    def test_segment_uri_resolved(self) -> None:
        result = parse_media_playlist(_load("media_vod.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.segments[0].uri == "http://cdn.example.com/live/seg0.ts"


class TestMediaPlaylistLive:
    def test_live_not_endlist(self) -> None:
        result = parse_media_playlist(_load("media_live.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.is_endlist is False

    def test_live_media_sequence(self) -> None:
        result = parse_media_playlist(_load("media_live.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.media_sequence == 1001

    def test_live_no_playlist_type(self) -> None:
        result = parse_media_playlist(_load("media_live.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.playlist_type is None


class TestMediaPlaylistEncrypted:
    def test_key_captured(self) -> None:
        result = parse_media_playlist(_load("media_encrypted.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        seg = result.segments[0]
        assert seg.key is not None
        assert seg.key["METHOD"] == "AES-128"
        assert "key.bin" in seg.key["URI"]
        assert seg.key["IV"] == "0x00000000000000000000000000000001"


class TestMediaPlaylistDiscontinuity:
    def test_discontinuity_flag(self) -> None:
        result = parse_media_playlist(_load("media_discontinuity.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.segments[0].discontinuity is False
        assert result.segments[1].discontinuity is True

    def test_discontinuity_sequence(self) -> None:
        result = parse_media_playlist(_load("media_discontinuity.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.discontinuity_sequence == 5


class TestMediaPlaylistByteRange:
    def test_byterange_values(self) -> None:
        result = parse_media_playlist(_load("media_byterange.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.segments[0].byterange == "1024@0"
        assert result.segments[1].byterange == "1024@1024"

    def test_map_info_captured(self) -> None:
        result = parse_media_playlist(_load("media_byterange.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        seg = result.segments[0]
        assert seg.map_info is not None
        assert "init.mp4" in seg.map_info["URI"]


class TestMediaPlaylistPDT:
    def test_program_date_time(self) -> None:
        result = parse_media_playlist(_load("media_pdt.m3u8"), BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert result.segments[0].program_date_time is not None
        assert "2024-01-15" in result.segments[0].program_date_time


class TestMediaPlaylistErrors:
    def test_master_as_media_returns_error(self) -> None:
        result = parse_media_playlist(_load("master_simple.m3u8"), BASE_URL)
        assert isinstance(result, ParseError)

    def test_empty_body(self) -> None:
        result = parse_media_playlist("", BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert len(result.segments) == 0

    def test_inline_simple(self) -> None:
        body = "#EXTM3U\n#EXT-X-TARGETDURATION:5\n#EXTINF:5.0,\nseg.ts\n#EXT-X-ENDLIST\n"
        result = parse_media_playlist(body, BASE_URL)
        assert isinstance(result, MediaPlaylist)
        assert len(result.segments) == 1
        assert result.is_endlist is True

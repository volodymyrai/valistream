"""Tests for master playlist parsing."""

from pathlib import Path

import pytest

from valistream.parser.master import parse_master_playlist
from valistream.parser.models import MasterPlaylist, ParseError

FIXTURES = Path(__file__).parent.parent / "fixtures"
BASE_URL = "http://cdn.example.com/live/master.m3u8"


def _load(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


class TestMasterPlaylistParsing:
    def test_simple_master(self) -> None:
        result = parse_master_playlist(_load("master_simple.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        assert result.version == 4
        assert len(result.variants) == 2

    def test_variant_bandwidth(self) -> None:
        result = parse_master_playlist(_load("master_simple.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        assert result.variants[0].bandwidth == 1280000
        assert result.variants[1].bandwidth == 2560000

    def test_variant_resolution(self) -> None:
        result = parse_master_playlist(_load("master_simple.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        assert result.variants[0].resolution == "1280x720"
        assert result.variants[1].resolution == "1920x1080"

    def test_variant_codecs(self) -> None:
        result = parse_master_playlist(_load("master_simple.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        assert result.variants[0].codecs == "avc1.4d401f,mp4a.40.2"

    def test_variant_uri_resolved(self) -> None:
        result = parse_master_playlist(_load("master_simple.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        assert result.variants[0].uri == "http://cdn.example.com/live/720p.m3u8"
        assert result.variants[1].uri == "http://cdn.example.com/live/1080p.m3u8"

    def test_master_with_audio_groups(self) -> None:
        result = parse_master_playlist(_load("master_with_audio.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        assert len(result.media) == 3

    def test_audio_rendition_fields(self) -> None:
        result = parse_master_playlist(_load("master_with_audio.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        en = result.media[0]
        assert en.name == "English"
        assert en.language == "en"
        assert en.type == "AUDIO"
        assert en.group_id == "audio"
        assert en.default is True

    def test_subtitle_rendition(self) -> None:
        result = parse_master_playlist(_load("master_with_audio.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        subs = [m for m in result.media if m.type == "SUBTITLES"]
        assert len(subs) == 1
        assert subs[0].language == "en"

    def test_independent_segments_flag(self) -> None:
        result = parse_master_playlist(_load("master_with_audio.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        assert result.is_independent_segments is True

    def test_variant_audio_group_ref(self) -> None:
        result = parse_master_playlist(_load("master_with_audio.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        assert result.variants[0].audio == "audio"
        assert result.variants[0].subtitles == "subs"

    def test_media_uri_resolved(self) -> None:
        result = parse_master_playlist(_load("master_with_audio.m3u8"), BASE_URL)
        assert isinstance(result, MasterPlaylist)
        assert result.media[0].uri == "http://cdn.example.com/live/audio_en.m3u8"

    def test_not_master_returns_error(self) -> None:
        result = parse_master_playlist(_load("media_vod.m3u8"), BASE_URL)
        assert isinstance(result, ParseError)


class TestMasterPlaylistInline:
    def test_single_variant_no_codecs(self) -> None:
        body = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000\nlow.m3u8\n"
        result = parse_master_playlist(body, BASE_URL)
        assert isinstance(result, MasterPlaylist)
        assert len(result.variants) == 1
        assert result.variants[0].codecs is None

    def test_empty_body_is_error(self) -> None:
        result = parse_master_playlist("", BASE_URL)
        assert isinstance(result, ParseError)

    @pytest.mark.parametrize(
        "body",
        [
            "garbage content\nnot a playlist",
            "#EXTM3U\n#EXT-X-VERSION:3\n",
        ],
        ids=["garbage", "m3u8-header-only"],
    )
    def test_invalid_bodies_return_error(self, body: str) -> None:
        result = parse_master_playlist(body, BASE_URL)
        assert isinstance(result, ParseError)

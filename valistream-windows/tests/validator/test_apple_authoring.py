"""Tests for Apple HLS Authoring Specification rules."""

import pytest

from valistream.parser.models import MasterPlaylist, MediaPlaylist, Rendition, Segment
from valistream.validator.apple_authoring import validate_apple_master, validate_apple_media
from valistream.validator.finding import FindingCode, Severity

URL = "http://cdn.example.com/stream.m3u8"


class TestCodecsAttribute:
    def test_missing_codecs(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1280000, resolution="1280x720")],
        )
        findings = validate_apple_master(playlist)
        codecs = [f for f in findings if f.code == FindingCode.APPLE_CODECS]
        assert len(codecs) == 1
        assert codecs[0].severity == Severity.WARNING

    def test_present_codecs(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1280000, codecs="avc1.4d401f,mp4a.40.2")],
        )
        findings = validate_apple_master(playlist)
        assert all(f.code != FindingCode.APPLE_CODECS for f in findings)


class TestAverageBandwidth:
    def test_missing_average_bandwidth(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1280000, codecs="avc1.4d401f")],
        )
        findings = validate_apple_master(playlist)
        avg = [f for f in findings if f.code == FindingCode.APPLE_AVERAGE_BANDWIDTH]
        assert len(avg) == 1

    def test_present_average_bandwidth(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1280000, codecs="avc1.4d401f", average_bandwidth=1000000)],
        )
        findings = validate_apple_master(playlist)
        assert all(f.code != FindingCode.APPLE_AVERAGE_BANDWIDTH for f in findings)


class TestResolution:
    def test_video_variant_missing_resolution(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1280000, codecs="avc1.4d401f")],
        )
        findings = validate_apple_master(playlist)
        res = [f for f in findings if f.code == FindingCode.APPLE_RESOLUTION]
        assert len(res) == 1

    def test_audio_only_no_resolution_ok(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="audio.m3u8", bandwidth=128000, codecs="mp4a.40.2")],
        )
        findings = validate_apple_master(playlist)
        assert all(f.code != FindingCode.APPLE_RESOLUTION for f in findings)

    def test_video_variant_with_resolution_ok(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1280000, codecs="avc1.4d401f", resolution="1280x720")],
        )
        findings = validate_apple_master(playlist)
        assert all(f.code != FindingCode.APPLE_RESOLUTION for f in findings)

    def test_no_codecs_expects_resolution(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1280000)],
        )
        findings = validate_apple_master(playlist)
        res = [f for f in findings if f.code == FindingCode.APPLE_RESOLUTION]
        assert len(res) == 1


class TestDuplicateBandwidth:
    def test_duplicate_bandwidth(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[
                Rendition(uri="a.m3u8", bandwidth=1280000, codecs="avc1.4d401f"),
                Rendition(uri="b.m3u8", bandwidth=1280000, codecs="avc1.4d401f"),
            ],
        )
        findings = validate_apple_master(playlist)
        dup = [f for f in findings if f.code == FindingCode.APPLE_VARIANT_LADDER]
        assert len(dup) == 1
        assert dup[0].details["bandwidth"] == 1280000

    def test_distinct_bandwidths(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[
                Rendition(uri="a.m3u8", bandwidth=1280000, codecs="avc1.4d401f"),
                Rendition(uri="b.m3u8", bandwidth=2560000, codecs="avc1.640028"),
            ],
        )
        findings = validate_apple_master(playlist)
        assert all(f.code != FindingCode.APPLE_VARIANT_LADDER for f in findings)


class TestIndependentSegments:
    def test_missing_independent_segments(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            is_independent_segments=False,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1280000, codecs="avc1.4d401f")],
        )
        findings = validate_apple_master(playlist)
        ind = [f for f in findings if f.code == FindingCode.APPLE_INDEPENDENT_SEGMENTS]
        assert len(ind) == 1

    def test_present_independent_segments(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            is_independent_segments=True,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1280000, codecs="avc1.4d401f")],
        )
        findings = validate_apple_master(playlist)
        assert all(f.code != FindingCode.APPLE_INDEPENDENT_SEGMENTS for f in findings)


class TestTargetDuration:
    def test_target_duration_above_6(self) -> None:
        playlist = MediaPlaylist(url=URL, target_duration=10.0)
        findings = validate_apple_media(playlist)
        assert len(findings) == 1
        assert findings[0].code == FindingCode.APPLE_TARGET_DURATION
        assert findings[0].severity == Severity.INFO

    def test_target_duration_at_6(self) -> None:
        playlist = MediaPlaylist(url=URL, target_duration=6.0)
        findings = validate_apple_media(playlist)
        assert len(findings) == 0

    def test_target_duration_below_6(self) -> None:
        playlist = MediaPlaylist(url=URL, target_duration=4.0)
        findings = validate_apple_media(playlist)
        assert len(findings) == 0

    def test_target_duration_none(self) -> None:
        playlist = MediaPlaylist(url=URL, target_duration=None)
        findings = validate_apple_media(playlist)
        assert len(findings) == 0

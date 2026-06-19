"""Tests for RFC 8216 validation rules."""

import pytest

from valistream.parser.models import MasterPlaylist, MediaPlaylist, Rendition, Segment
from valistream.validator.finding import FindingCode, Severity
from valistream.validator.rfc8216 import validate_rfc8216_master, validate_rfc8216_media

URL = "http://cdn.example.com/stream.m3u8"


# ── Media playlist rules ──


class TestMissingTargetDuration:
    def test_missing_target_duration(self) -> None:
        playlist = MediaPlaylist(url=URL, target_duration=None)
        findings = validate_rfc8216_media(playlist)
        assert len(findings) == 1
        assert findings[0].code == FindingCode.RFC8216_4_3_3_1
        assert findings[0].severity == Severity.ERROR

    def test_present_target_duration(self) -> None:
        playlist = MediaPlaylist(url=URL, target_duration=10.0)
        findings = validate_rfc8216_media(playlist)
        assert all(f.code != FindingCode.RFC8216_4_3_3_1 for f in findings)


class TestSegmentDurationExceedsTarget:
    def test_segment_exceeds_target(self) -> None:
        playlist = MediaPlaylist(
            url=URL,
            target_duration=10.0,
            segments=[
                Segment(uri="ok.ts", duration=9.5),
                Segment(uri="bad.ts", duration=11.5),
            ],
        )
        findings = validate_rfc8216_media(playlist)
        duration_findings = [f for f in findings if f.code == FindingCode.RFC8216_4_3_3_1_DURATION]
        assert len(duration_findings) == 1
        assert duration_findings[0].details["duration"] == 11.5

    def test_segment_rounds_to_target_ok(self) -> None:
        playlist = MediaPlaylist(
            url=URL,
            target_duration=10.0,
            segments=[Segment(uri="ok.ts", duration=10.4)],
        )
        findings = validate_rfc8216_media(playlist)
        assert all(f.code != FindingCode.RFC8216_4_3_3_1_DURATION for f in findings)

    def test_no_segments_no_findings(self) -> None:
        playlist = MediaPlaylist(url=URL, target_duration=10.0, segments=[])
        findings = validate_rfc8216_media(playlist)
        assert all(f.code != FindingCode.RFC8216_4_3_3_1_DURATION for f in findings)

    def test_no_target_skips_check(self) -> None:
        playlist = MediaPlaylist(
            url=URL,
            target_duration=None,
            segments=[Segment(uri="seg.ts", duration=999.0)],
        )
        findings = validate_rfc8216_media(playlist)
        assert all(f.code != FindingCode.RFC8216_4_3_3_1_DURATION for f in findings)


# ── Master playlist rules ──


class TestVariantBandwidth:
    def test_missing_bandwidth(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="low.m3u8", bandwidth=0)],
        )
        findings = validate_rfc8216_master(playlist)
        bw = [f for f in findings if f.code == FindingCode.RFC8216_4_3_4_2_BANDWIDTH]
        assert len(bw) == 1

    def test_valid_bandwidth(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="low.m3u8", bandwidth=500000)],
        )
        findings = validate_rfc8216_master(playlist)
        assert all(f.code != FindingCode.RFC8216_4_3_4_2_BANDWIDTH for f in findings)


class TestMediaRequiredAttributes:
    def test_missing_type(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            media=[Rendition(uri="en.m3u8", group_id="audio", name="English")],
        )
        findings = validate_rfc8216_master(playlist)
        attr = [f for f in findings if f.code == FindingCode.RFC8216_4_3_4_1]
        assert len(attr) == 1
        assert "TYPE" in attr[0].details["missing"]

    def test_missing_multiple(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            media=[Rendition(uri="x.m3u8")],
        )
        findings = validate_rfc8216_master(playlist)
        attr = [f for f in findings if f.code == FindingCode.RFC8216_4_3_4_1]
        assert len(attr) == 1
        missing = attr[0].details["missing"]
        assert "TYPE" in missing
        assert "GROUP-ID" in missing
        assert "NAME" in missing

    def test_all_present(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            media=[Rendition(uri="en.m3u8", type="AUDIO", group_id="audio", name="English")],
        )
        findings = validate_rfc8216_master(playlist)
        assert all(f.code != FindingCode.RFC8216_4_3_4_1 for f in findings)


class TestGroupReferences:
    def test_invalid_audio_group(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1000000, audio="nonexistent")],
            media=[Rendition(uri="en.m3u8", type="AUDIO", group_id="audio", name="English")],
        )
        findings = validate_rfc8216_master(playlist)
        grp = [f for f in findings if f.code == FindingCode.RFC8216_4_3_4_2_1]
        assert len(grp) == 1
        assert grp[0].details["group"] == "nonexistent"

    def test_valid_audio_group(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1000000, audio="audio")],
            media=[Rendition(uri="en.m3u8", type="AUDIO", group_id="audio", name="English")],
        )
        findings = validate_rfc8216_master(playlist)
        assert all(f.code != FindingCode.RFC8216_4_3_4_2_1 for f in findings)

    def test_none_value_skipped(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1000000, closed_captions="NONE")],
        )
        findings = validate_rfc8216_master(playlist)
        assert all(f.code != FindingCode.RFC8216_4_3_4_2_1 for f in findings)

    def test_invalid_subtitles_group(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=1000000, subtitles="missing")],
            media=[Rendition(uri="en.m3u8", type="SUBTITLES", group_id="subs", name="English")],
        )
        findings = validate_rfc8216_master(playlist)
        grp = [f for f in findings if f.code == FindingCode.RFC8216_4_3_4_2_1]
        assert len(grp) == 1


class TestCleanPlaylist:
    def test_well_formed_master(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[
                Rendition(uri="720p.m3u8", bandwidth=1280000, resolution="1280x720", codecs="avc1.4d401f"),
                Rendition(uri="1080p.m3u8", bandwidth=2560000, resolution="1920x1080", codecs="avc1.640028"),
            ],
            media=[
                Rendition(uri="en.m3u8", type="AUDIO", group_id="audio", name="English", language="en"),
            ],
        )
        findings = validate_rfc8216_master(playlist)
        errors = [f for f in findings if f.severity == Severity.ERROR]
        assert len(errors) == 0

    def test_well_formed_media(self) -> None:
        playlist = MediaPlaylist(
            url=URL,
            target_duration=10.0,
            segments=[
                Segment(uri="seg0.ts", duration=9.5),
                Segment(uri="seg1.ts", duration=10.0),
            ],
        )
        findings = validate_rfc8216_media(playlist)
        assert len(findings) == 0

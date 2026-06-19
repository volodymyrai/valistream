"""Tests for the validation engine orchestrator."""

from valistream.parser.models import MasterPlaylist, MediaPlaylist, Rendition, Segment
from valistream.validator.engine import validate_master, validate_media
from valistream.validator.finding import Severity

URL = "http://cdn.example.com/stream.m3u8"


class TestValidateMaster:
    def test_runs_both_rfc_and_apple(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            variants=[Rendition(uri="720p.m3u8", bandwidth=0)],
        )
        findings = validate_master(playlist)
        codes = {f.code.value for f in findings}
        assert "RFC8216.4.3.4.2-BANDWIDTH" in codes
        assert "APPLE.codecs" in codes

    def test_clean_master_no_errors(self) -> None:
        playlist = MasterPlaylist(
            url=URL,
            is_independent_segments=True,
            variants=[
                Rendition(
                    uri="720p.m3u8", bandwidth=1280000,
                    resolution="1280x720", codecs="avc1.4d401f,mp4a.40.2",
                    average_bandwidth=1000000,
                ),
            ],
        )
        findings = validate_master(playlist)
        errors = [f for f in findings if f.severity == Severity.ERROR]
        assert len(errors) == 0


class TestValidateMedia:
    def test_runs_both_rfc_and_apple(self) -> None:
        playlist = MediaPlaylist(
            url=URL,
            target_duration=10.0,
            segments=[Segment(uri="seg0.ts", duration=9.0)],
        )
        findings = validate_media(playlist)
        codes = {f.code.value for f in findings}
        assert "APPLE.target-duration" in codes

    def test_clean_media_no_findings(self) -> None:
        playlist = MediaPlaylist(
            url=URL,
            target_duration=6.0,
            segments=[
                Segment(uri="seg0.ts", duration=5.5),
                Segment(uri="seg1.ts", duration=6.0),
            ],
        )
        findings = validate_media(playlist)
        assert len(findings) == 0

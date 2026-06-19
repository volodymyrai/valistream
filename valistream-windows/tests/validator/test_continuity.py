"""Tests for live stream continuity validation."""

import pytest

from valistream.parser.models import MediaPlaylist, Segment
from valistream.validator.continuity import check_continuity
from valistream.validator.finding import FindingCode, Severity

URL = "http://cdn.example.com/live/720p.m3u8"


def _playlist(seq: int, segments: list[Segment], disc_seq: int = 0) -> MediaPlaylist:
    return MediaPlaylist(
        url=URL,
        target_duration=6.0,
        media_sequence=seq,
        discontinuity_sequence=disc_seq,
        segments=segments,
    )


def _segs(*uris: str, duration: float = 6.0) -> list[Segment]:
    return [Segment(uri=u, duration=duration) for u in uris]


class TestMediaSequenceRegression:
    def test_regression_detected(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts", "c.ts"))
        curr = _playlist(99, _segs("x.ts", "y.ts", "z.ts"))
        findings = check_continuity(prev, curr)
        seq = [f for f in findings if f.code == FindingCode.CONTINUITY_MEDIA_SEQUENCE]
        assert len(seq) == 1
        assert seq[0].severity == Severity.ERROR
        assert seq[0].details["previousMediaSequence"] == 100
        assert seq[0].details["currentMediaSequence"] == 99

    def test_regression_short_circuits(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts"))
        curr = _playlist(50, _segs("x.ts"))
        findings = check_continuity(prev, curr)
        assert all(f.code == FindingCode.CONTINUITY_MEDIA_SEQUENCE for f in findings)

    def test_same_sequence_ok(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts"))
        curr = _playlist(100, _segs("a.ts", "b.ts"))
        findings = check_continuity(prev, curr)
        assert all(f.code != FindingCode.CONTINUITY_MEDIA_SEQUENCE for f in findings)

    def test_advancing_ok(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts", "c.ts"))
        curr = _playlist(101, _segs("b.ts", "c.ts", "d.ts"))
        findings = check_continuity(prev, curr)
        assert all(f.code != FindingCode.CONTINUITY_MEDIA_SEQUENCE for f in findings)


class TestHeadRemoval:
    def test_too_fast_removal(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts"))
        curr = _playlist(103, _segs("d.ts", "e.ts"))
        findings = check_continuity(prev, curr)
        head = [f for f in findings if f.code == FindingCode.CONTINUITY_HEAD_REMOVAL]
        assert len(head) == 1
        assert head[0].details["advancedBy"] == 3
        assert head[0].details["previousSegmentCount"] == 2

    def test_normal_advance(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts", "c.ts"))
        curr = _playlist(102, _segs("c.ts", "d.ts", "e.ts"))
        findings = check_continuity(prev, curr)
        assert all(f.code != FindingCode.CONTINUITY_HEAD_REMOVAL for f in findings)


class TestSegmentStability:
    def test_uri_changed(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts", "c.ts"))
        curr = _playlist(101, [
            Segment(uri="CHANGED.ts", duration=6.0),
            Segment(uri="c.ts", duration=6.0),
            Segment(uri="d.ts", duration=6.0),
        ])
        findings = check_continuity(prev, curr)
        stab = [f for f in findings if f.code == FindingCode.CONTINUITY_SEGMENT_STABILITY]
        assert len(stab) == 1
        assert stab[0].details["mediaSequence"] == 101
        assert stab[0].details["previousURI"] == "b.ts"
        assert stab[0].details["currentURI"] == "CHANGED.ts"

    def test_duration_changed(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts"))
        curr = _playlist(100, [
            Segment(uri="a.ts", duration=5.0),
            Segment(uri="b.ts", duration=6.0),
        ])
        findings = check_continuity(prev, curr)
        stab = [f for f in findings if f.code == FindingCode.CONTINUITY_SEGMENT_STABILITY]
        assert len(stab) == 1

    def test_stable_segments(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts", "c.ts"))
        curr = _playlist(101, _segs("b.ts", "c.ts", "d.ts"))
        findings = check_continuity(prev, curr)
        assert all(f.code != FindingCode.CONTINUITY_SEGMENT_STABILITY for f in findings)


class TestDiscontinuitySequence:
    def test_regression_detected(self) -> None:
        prev = _playlist(100, _segs("a.ts"), disc_seq=5)
        curr = _playlist(101, _segs("b.ts"), disc_seq=3)
        findings = check_continuity(prev, curr)
        disc = [f for f in findings if f.code == FindingCode.CONTINUITY_DISCONTINUITY_SEQUENCE]
        assert len(disc) == 1
        assert disc[0].details["previousDiscontinuitySequence"] == 5
        assert disc[0].details["currentDiscontinuitySequence"] == 3

    def test_same_sequence_ok(self) -> None:
        prev = _playlist(100, _segs("a.ts"), disc_seq=5)
        curr = _playlist(101, _segs("b.ts"), disc_seq=5)
        findings = check_continuity(prev, curr)
        assert all(f.code != FindingCode.CONTINUITY_DISCONTINUITY_SEQUENCE for f in findings)

    def test_increasing_ok(self) -> None:
        prev = _playlist(100, _segs("a.ts"), disc_seq=5)
        curr = _playlist(101, _segs("b.ts"), disc_seq=6)
        findings = check_continuity(prev, curr)
        assert all(f.code != FindingCode.CONTINUITY_DISCONTINUITY_SEQUENCE for f in findings)


class TestDiscontinuityInserted:
    def test_new_discontinuity_at_tail(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts"))
        curr = _playlist(101, [
            Segment(uri="b.ts", duration=6.0),
            Segment(uri="c.ts", duration=6.0, discontinuity=True),
        ])
        findings = check_continuity(prev, curr)
        disc = [f for f in findings if f.code == FindingCode.CONTINUITY_DISCONTINUITY_INSERTED]
        assert len(disc) == 1
        assert disc[0].severity == Severity.INFO
        assert disc[0].details["mediaSequence"] == 102

    def test_existing_discontinuity_not_reported(self) -> None:
        prev = _playlist(100, [
            Segment(uri="a.ts", duration=6.0),
            Segment(uri="b.ts", duration=6.0, discontinuity=True),
        ])
        curr = _playlist(100, [
            Segment(uri="a.ts", duration=6.0),
            Segment(uri="b.ts", duration=6.0, discontinuity=True),
        ])
        findings = check_continuity(prev, curr)
        assert all(f.code != FindingCode.CONTINUITY_DISCONTINUITY_INSERTED for f in findings)


class TestNormalLiveProgression:
    def test_clean_progression(self) -> None:
        prev = _playlist(100, _segs("a.ts", "b.ts", "c.ts"))
        curr = _playlist(101, _segs("b.ts", "c.ts", "d.ts"))
        findings = check_continuity(prev, curr)
        errors = [f for f in findings if f.severity == Severity.ERROR]
        assert len(errors) == 0

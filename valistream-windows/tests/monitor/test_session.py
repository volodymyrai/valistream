"""Tests for SessionState, session ID generation, and rendition selection."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone

import pytest

from valistream.parser.models import MasterPlaylist, Rendition, StreamType
from valistream.monitor.session import (
    SessionState,
    classify_stream,
    make_session_id,
    select_renditions,
)
from valistream.validator.finding import Finding, FindingCode, Severity


# ── Session ID ──


class TestMakeSessionId:
    def test_format_with_host_and_path(self) -> None:
        ts = datetime(2024, 3, 15, 14, 30, 0, tzinfo=timezone.utc)
        sid = make_session_id("https://cdn.example.com/live/master.m3u8", now=ts)
        assert sid == "20240315T143000_cdn-example-com-master-m3u8"

    def test_format_host_only(self) -> None:
        ts = datetime(2024, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
        sid = make_session_id("https://cdn.example.com/", now=ts)
        assert sid == "20240101T000000_cdn-example-com"

    def test_windows_safe_characters(self) -> None:
        ts = datetime(2024, 6, 1, 12, 0, 0, tzinfo=timezone.utc)
        sid = make_session_id("https://host/path?q=1&x=2", now=ts)
        assert all(c.isalnum() or c in "-_" for c in sid)

    def test_long_slug_truncated(self) -> None:
        ts = datetime(2024, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
        sid = make_session_id(
            "https://verylongdomainname.example.com/some-very-long-path-that-should-be-truncated.m3u8",
            now=ts,
        )
        parts = sid.split("_", 1)
        assert len(parts[1]) <= 40

    def test_uses_utc_now_when_no_timestamp(self) -> None:
        sid = make_session_id("https://example.com/live.m3u8")
        assert len(sid.split("_")[0]) == 15  # YYYYMMDDTHHMMSS


# ── Stream classification ──


class TestClassifyStream:
    def test_vod_with_endlist(self) -> None:
        body = "#EXTM3U\n#EXT-X-ENDLIST\n"
        assert classify_stream(body) == StreamType.VOD

    def test_live_without_endlist(self) -> None:
        body = "#EXTM3U\n#EXTINF:6.0,\nseg0.ts\n"
        assert classify_stream(body) == StreamType.LIVE


# ── Rendition selection ──

URL = "https://cdn.example.com/master.m3u8"


def _master_with_variants(*args: tuple[str, int, str | None, str | None]) -> MasterPlaylist:
    variants = [
        Rendition(uri=uri, bandwidth=bw, resolution=res, codecs=codecs)
        for uri, bw, res, codecs in args
    ]
    return MasterPlaylist(url=URL, variants=variants)


class TestSelectRenditions:
    def test_all_when_no_preselect(self) -> None:
        master = _master_with_variants(
            ("720p.m3u8", 1280000, "1280x720", "avc1.4d401f"),
            ("1080p.m3u8", 2560000, "1920x1080", "avc1.640028"),
        )
        selected = select_renditions(master)
        assert len(selected) == 2

    def test_filter_by_resolution(self) -> None:
        master = _master_with_variants(
            ("720p.m3u8", 1280000, "1280x720", "avc1.4d401f"),
            ("1080p.m3u8", 2560000, "1920x1080", "avc1.640028"),
        )
        selected = select_renditions(master, preselect="720")
        assert len(selected) == 1
        assert selected[0].resolution == "1280x720"

    def test_filter_by_bandwidth(self) -> None:
        master = _master_with_variants(
            ("low.m3u8", 500000, None, None),
            ("high.m3u8", 5000000, None, None),
        )
        selected = select_renditions(master, preselect="5000000")
        assert len(selected) == 1
        assert selected[0].bandwidth == 5000000

    def test_filter_by_uri(self) -> None:
        master = _master_with_variants(
            ("720p.m3u8", 1280000, "1280x720", None),
            ("1080p.m3u8", 2560000, "1920x1080", None),
        )
        selected = select_renditions(master, preselect="1080p")
        assert len(selected) == 1
        assert selected[0].uri == "1080p.m3u8"

    def test_no_match_falls_back_to_all(self) -> None:
        master = _master_with_variants(
            ("720p.m3u8", 1280000, "1280x720", None),
        )
        selected = select_renditions(master, preselect="4K")
        assert len(selected) == 1  # fallback to all

    def test_empty_variants(self) -> None:
        master = MasterPlaylist(url=URL, variants=[])
        selected = select_renditions(master)
        assert selected == []

    def test_case_insensitive(self) -> None:
        master = _master_with_variants(
            ("720P.m3u8", 1280000, "1280x720", "AVC1.4d401f"),
        )
        selected = select_renditions(master, preselect="avc1")
        assert len(selected) == 1


# ── SessionState ──


class TestSessionState:
    def test_add_finding(self) -> None:
        state = SessionState()
        finding = Finding(
            code=FindingCode.RFC8216_4_3_3_1,
            severity=Severity.ERROR,
            message="test",
        )
        state.add_finding(finding)
        assert len(state.findings) == 1

    def test_add_findings_batch(self) -> None:
        state = SessionState()
        findings = [
            Finding(code=FindingCode.RFC8216_4_3_3_1, severity=Severity.ERROR, message="a"),
            Finding(code=FindingCode.APPLE_CODECS, severity=Severity.WARNING, message="b"),
        ]
        state.add_findings(findings)
        assert len(state.findings) == 2

    def test_finish_sets_ended_at(self) -> None:
        state = SessionState()
        assert state.ended_at is None
        state.finish()
        assert state.ended_at is not None

    def test_defaults(self) -> None:
        state = SessionState()
        assert state.session_id == ""
        assert state.url == ""
        assert state.output_dir is None
        assert state.stream_type is None
        assert state.selected_renditions == []
        assert state.findings == []
        assert state.cancelled is False
        assert state.started_at is not None

    def test_lock_is_asyncio_lock(self) -> None:
        state = SessionState()
        assert isinstance(state.lock, asyncio.Lock)

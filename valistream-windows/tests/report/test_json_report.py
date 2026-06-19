"""Tests for report.json generation — schema v1."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from valistream.monitor.session import SessionState
from valistream.parser.models import Rendition, StreamType
from valistream.report.json_report import build_report_dict, generate_json_report
from valistream.validator.finding import Finding, FindingCode, Severity


def _session(
    *,
    findings: list[Finding] | None = None,
    renditions: list[Rendition] | None = None,
    stream_type: StreamType = StreamType.VOD,
    cancelled: bool = False,
    ended: bool = True,
) -> SessionState:
    s = SessionState(
        session_id="20240315T143000_cdn-example-com",
        url="https://cdn.example.com/master.m3u8",
        stream_type=stream_type,
        started_at=datetime(2024, 3, 15, 14, 30, 0, tzinfo=timezone.utc),
        cancelled=cancelled,
    )
    if ended:
        s.ended_at = datetime(2024, 3, 15, 14, 30, 5, tzinfo=timezone.utc)
    s.selected_renditions = renditions or []
    if findings:
        s.add_findings(findings)
    return s


RENDITION_720 = Rendition(
    uri="720p.m3u8",
    bandwidth=1280000,
    resolution="1280x720",
    codecs="avc1.4d401f,mp4a.40.2",
    average_bandwidth=1000000,
)


class TestBuildReportDict:
    def test_schema_version(self) -> None:
        report = build_report_dict(_session())
        assert report["schema_version"] == 1

    def test_session_fields(self) -> None:
        report = build_report_dict(_session())
        session = report["session"]
        assert session["id"] == "20240315T143000_cdn-example-com"
        assert session["url"] == "https://cdn.example.com/master.m3u8"
        assert session["started_at"] is not None
        assert session["ended_at"] is not None
        assert session["duration_s"] == 5.0
        assert session["state"] == "completed"

    def test_cancelled_state(self) -> None:
        report = build_report_dict(_session(cancelled=True))
        assert report["session"]["state"] == "cancelled"

    def test_in_progress_state(self) -> None:
        report = build_report_dict(_session(ended=False))
        assert report["session"]["state"] == "in_progress"

    def test_stream_kind(self) -> None:
        report = build_report_dict(_session(stream_type=StreamType.LIVE))
        assert report["stream"]["kind"] == "live"

    def test_findings_serialization(self) -> None:
        findings = [
            Finding(
                code=FindingCode.RFC8216_4_3_4_2_BANDWIDTH,
                severity=Severity.ERROR,
                message="BANDWIDTH must be > 0",
            ),
            Finding(
                code=FindingCode.APPLE_CODECS,
                severity=Severity.WARNING,
                message="Missing CODECS",
            ),
        ]
        report = build_report_dict(_session(findings=findings))
        assert len(report["findings"]) == 2
        assert report["findings"][0]["code"] == "RFC8216.4.3.4.2-BANDWIDTH"
        assert report["findings"][0]["severity"] == "error"
        assert report["findings"][1]["severity"] == "warning"

    def test_finding_optional_fields(self) -> None:
        findings = [
            Finding(
                code=FindingCode.RFC8216_4_3_3_1_DURATION,
                severity=Severity.ERROR,
                message="Duration exceeds target",
                playlist_url="https://cdn.example.com/720p.m3u8",
                line=5,
                details={"expected": 6.0, "actual": 12.0},
            ),
        ]
        report = build_report_dict(_session(findings=findings))
        f = report["findings"][0]
        assert f["spec_ref"] == "RFC 8216 §4.3.3.1"
        assert f["playlist_url"] == "https://cdn.example.com/720p.m3u8"
        assert f["line"] == 5
        assert f["details"] == {"expected": 6.0, "actual": 12.0}

    def test_renditions_serialization(self) -> None:
        report = build_report_dict(_session(renditions=[RENDITION_720]))
        assert len(report["renditions"]) == 1
        r = report["renditions"][0]
        assert r["uri"] == "720p.m3u8"
        assert r["bandwidth"] == 1280000
        assert r["resolution"] == "1280x720"
        assert r["codecs"] == "avc1.4d401f,mp4a.40.2"

    def test_summary_counts(self) -> None:
        findings = [
            Finding(code=FindingCode.RFC8216_4_3_4_2_BANDWIDTH, severity=Severity.ERROR, message="a"),
            Finding(code=FindingCode.APPLE_CODECS, severity=Severity.WARNING, message="b"),
            Finding(code=FindingCode.APPLE_CODECS, severity=Severity.WARNING, message="c"),
            Finding(code=FindingCode.APPLE_RESOLUTION, severity=Severity.INFO, message="d"),
        ]
        report = build_report_dict(_session(findings=findings))
        summary = report["summary"]
        assert summary["total"] == 4
        assert summary["counts_by_severity"]["error"] == 1
        assert summary["counts_by_severity"]["warning"] == 2
        assert summary["counts_by_severity"]["info"] == 1

    def test_empty_findings(self) -> None:
        report = build_report_dict(_session())
        assert report["findings"] == []
        assert report["summary"]["total"] == 0


class TestGenerateJsonReport:
    def test_writes_valid_json_file(self, tmp_path: Path) -> None:
        output = tmp_path / "report.json"
        generate_json_report(_session(renditions=[RENDITION_720]), output)
        parsed = json.loads(output.read_text(encoding="utf-8"))
        assert parsed["schema_version"] == 1

    def test_creates_parent_dirs(self, tmp_path: Path) -> None:
        output = tmp_path / "nested" / "dir" / "report.json"
        generate_json_report(_session(), output)
        assert output.exists()

    def test_snapshot_match(self, tmp_path: Path) -> None:
        """A known session produces a predictable JSON structure."""
        findings = [
            Finding(
                code=FindingCode.RFC8216_4_3_4_2_BANDWIDTH,
                severity=Severity.ERROR,
                message="BANDWIDTH must be > 0",
            ),
        ]
        session = _session(findings=findings, renditions=[RENDITION_720])
        output = tmp_path / "report.json"
        generate_json_report(session, output)

        report = json.loads(output.read_text(encoding="utf-8"))

        assert report["schema_version"] == 1
        assert report["session"]["id"] == "20240315T143000_cdn-example-com"
        assert report["session"]["state"] == "completed"
        assert report["session"]["duration_s"] == 5.0
        assert report["stream"]["kind"] == "vod"
        assert len(report["findings"]) == 1
        assert report["findings"][0]["code"] == "RFC8216.4.3.4.2-BANDWIDTH"
        assert len(report["renditions"]) == 1
        assert report["renditions"][0]["uri"] == "720p.m3u8"
        assert report["summary"]["total"] == 1
        assert report["summary"]["counts_by_severity"]["error"] == 1

"""Tests for report.md generation."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import pytest

from valistream.monitor.session import SessionState
from valistream.parser.models import Rendition, StreamType
from valistream.report.markdown import build_markdown, generate_markdown_report
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

RENDITION_1080 = Rendition(
    uri="1080p.m3u8",
    bandwidth=2560000,
    resolution="1920x1080",
    codecs="avc1.640028",
    average_bandwidth=2000000,
)


class TestBuildMarkdown:
    def test_header_present(self) -> None:
        md = build_markdown(_session())
        assert "# Valistream Report" in md

    def test_session_id_in_header(self) -> None:
        md = build_markdown(_session())
        assert "20240315T143000_cdn-example-com" in md

    def test_url_in_header(self) -> None:
        md = build_markdown(_session())
        assert "https://cdn.example.com/master.m3u8" in md

    def test_stream_type(self) -> None:
        md = build_markdown(_session(stream_type=StreamType.LIVE))
        assert "LIVE" in md

    def test_cancelled_state(self) -> None:
        md = build_markdown(_session(cancelled=True))
        assert "cancelled" in md

    def test_findings_summary_table(self) -> None:
        findings = [
            Finding(code=FindingCode.RFC8216_4_3_4_2_BANDWIDTH, severity=Severity.ERROR, message="err"),
            Finding(code=FindingCode.APPLE_CODECS, severity=Severity.WARNING, message="warn"),
        ]
        md = build_markdown(_session(findings=findings))
        assert "| Error | 1 |" in md
        assert "| Warning | 1 |" in md
        assert "| **Total** | **2** |" in md

    def test_findings_detail_section(self) -> None:
        findings = [
            Finding(
                code=FindingCode.RFC8216_4_3_4_2_BANDWIDTH,
                severity=Severity.ERROR,
                message="BANDWIDTH must be > 0",
            ),
        ]
        md = build_markdown(_session(findings=findings))
        assert "## Findings" in md
        assert "RFC8216.4.3.4.2-BANDWIDTH" in md
        assert "BANDWIDTH must be > 0" in md

    def test_error_before_warning_before_info(self) -> None:
        findings = [
            Finding(code=FindingCode.APPLE_RESOLUTION, severity=Severity.INFO, message="info msg"),
            Finding(code=FindingCode.APPLE_CODECS, severity=Severity.WARNING, message="warn msg"),
            Finding(code=FindingCode.RFC8216_4_3_4_2_BANDWIDTH, severity=Severity.ERROR, message="err msg"),
        ]
        md = build_markdown(_session(findings=findings))
        error_pos = md.index("ERRORS")
        warning_pos = md.index("WARNINGS")
        info_pos = md.index("INFOS")
        assert error_pos < warning_pos < info_pos

    def test_no_findings_section_when_empty(self) -> None:
        md = build_markdown(_session())
        assert "\n## Findings\n" not in md

    def test_rendition_table(self) -> None:
        md = build_markdown(_session(renditions=[RENDITION_720, RENDITION_1080]))
        assert "## Renditions" in md
        assert "1280x720" in md
        assert "1920x1080" in md

    def test_legend_section(self) -> None:
        md = build_markdown(_session(renditions=[RENDITION_720]))
        assert "## Legend" in md
        assert "720p.m3u8" in md

    def test_no_renditions_no_table(self) -> None:
        md = build_markdown(_session())
        assert "## Renditions" not in md
        assert "## Legend" not in md

    def test_duration_shown(self) -> None:
        md = build_markdown(_session())
        assert "5.0s" in md

    def test_playlist_url_in_finding(self) -> None:
        findings = [
            Finding(
                code=FindingCode.DELIVERY_CONTENT_TYPE,
                severity=Severity.WARNING,
                message="Unexpected content type",
                playlist_url="https://cdn.example.com/720p.m3u8",
            ),
        ]
        md = build_markdown(_session(findings=findings))
        assert "https://cdn.example.com/720p.m3u8" in md


class TestGenerateMarkdownReport:
    def test_writes_file(self, tmp_path: Path) -> None:
        output = tmp_path / "report.md"
        generate_markdown_report(_session(renditions=[RENDITION_720]), output)
        text = output.read_text(encoding="utf-8")
        assert "# Valistream Report" in text

    def test_creates_parent_dirs(self, tmp_path: Path) -> None:
        output = tmp_path / "nested" / "report.md"
        generate_markdown_report(_session(), output)
        assert output.exists()

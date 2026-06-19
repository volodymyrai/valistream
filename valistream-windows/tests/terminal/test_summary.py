"""Tests for session summary output."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from io import StringIO
from pathlib import Path

from rich.console import Console

from valistream.monitor.session import SessionState
from valistream.parser.models import StreamType
from valistream.terminal.summary import print_summary, print_summary_json
from valistream.validator.finding import Finding, FindingCode, Severity


def _session(
    *,
    findings: list[Finding] | None = None,
    ended: bool = True,
    output_dir: Path | None = None,
) -> SessionState:
    s = SessionState(
        session_id="20240315T143000_test",
        url="https://cdn.example.com/master.m3u8",
        stream_type=StreamType.VOD,
        started_at=datetime(2024, 3, 15, 14, 30, 0, tzinfo=timezone.utc),
    )
    if ended:
        s.ended_at = datetime(2024, 3, 15, 14, 30, 5, tzinfo=timezone.utc)
    if output_dir:
        s.output_dir = output_dir
    if findings:
        s.add_findings(findings)
    return s


class TestPrintSummary:
    def test_contains_session_summary(self) -> None:
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_summary(console, _session())
        output = buf.getvalue()
        assert "Session Summary" in output

    def test_shows_duration(self) -> None:
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_summary(console, _session())
        output = buf.getvalue()
        assert "5.0s" in output

    def test_shows_finding_counts(self) -> None:
        findings = [
            Finding(code=FindingCode.RFC8216_4_3_4_2_BANDWIDTH, severity=Severity.ERROR, message="a"),
            Finding(code=FindingCode.APPLE_CODECS, severity=Severity.WARNING, message="b"),
            Finding(code=FindingCode.APPLE_RESOLUTION, severity=Severity.INFO, message="c"),
        ]
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_summary(console, _session(findings=findings))
        output = buf.getvalue()
        assert "3" in output

    def test_shows_output_dir(self) -> None:
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_summary(console, _session(output_dir=Path("/tmp/sessions/test")))
        output = buf.getvalue()
        assert "sessions" in output

    def test_in_progress_duration(self) -> None:
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_summary(console, _session(ended=False))
        output = buf.getvalue()
        assert "in progress" in output


class TestPrintSummaryJson:
    def test_outputs_valid_json(self) -> None:
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_summary_json(_session())
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        assert parsed["type"] == "summary"
        assert parsed["session_id"] == "20240315T143000_test"

    def test_state_completed(self) -> None:
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_summary_json(_session())
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        assert parsed["state"] == "completed"

    def test_duration(self) -> None:
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_summary_json(_session())
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        assert parsed["duration_s"] == 5.0

    def test_finding_counts(self) -> None:
        findings = [
            Finding(code=FindingCode.RFC8216_4_3_4_2_BANDWIDTH, severity=Severity.ERROR, message="a"),
            Finding(code=FindingCode.APPLE_CODECS, severity=Severity.WARNING, message="b"),
        ]
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_summary_json(_session(findings=findings))
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        assert parsed["errors"] == 1
        assert parsed["warnings"] == 1
        assert parsed["total_findings"] == 2

    def test_sorted_keys(self) -> None:
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_summary_json(_session())
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        keys = list(parsed.keys())
        assert keys == sorted(keys)

    def test_includes_output_dir(self) -> None:
        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_summary_json(_session(output_dir=Path("/tmp/test")))
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        assert "output_dir" in parsed

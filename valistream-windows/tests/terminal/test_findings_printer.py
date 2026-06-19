"""Tests for colored findings output."""

from __future__ import annotations

import json
from io import StringIO

from rich.console import Console

from valistream.terminal.findings_printer import print_finding, print_finding_json
from valistream.validator.finding import Finding, FindingCode, Severity


def _make_finding(
    severity: Severity = Severity.ERROR,
    code: FindingCode = FindingCode.RFC8216_4_3_4_2_BANDWIDTH,
    message: str = "test error",
    **kwargs: object,
) -> Finding:
    return Finding(code=code, severity=severity, message=message, **kwargs)


class TestPrintFinding:
    def test_error_contains_severity(self) -> None:
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_finding(console, _make_finding())
        output = buf.getvalue()
        assert "ERROR" in output

    def test_warning_contains_severity(self) -> None:
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_finding(console, _make_finding(severity=Severity.WARNING))
        output = buf.getvalue()
        assert "WARNING" in output

    def test_info_contains_severity(self) -> None:
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_finding(console, _make_finding(severity=Severity.INFO))
        output = buf.getvalue()
        assert "INFO" in output

    def test_contains_code(self) -> None:
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_finding(console, _make_finding())
        output = buf.getvalue()
        assert "RFC8216.4.3.4.2-BANDWIDTH" in output

    def test_contains_message(self) -> None:
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_finding(console, _make_finding(message="my error message"))
        output = buf.getvalue()
        assert "my error message" in output

    def test_rendition_alias_shown(self) -> None:
        buf = StringIO()
        console = Console(file=buf, force_terminal=True, color_system="truecolor")
        print_finding(console, _make_finding(), rendition_alias="video-720p")
        output = buf.getvalue()
        assert "rendition: video-720p" in output

    def test_no_color_mode(self) -> None:
        buf = StringIO()
        console = Console(file=buf, no_color=True)
        print_finding(console, _make_finding())
        output = buf.getvalue()
        assert "\x1b[" not in output


class TestPrintFindingJson:
    def test_outputs_valid_json(self, capsys: object) -> None:
        import sys
        from io import StringIO

        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_finding_json(_make_finding())
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        assert parsed["code"] == "RFC8216.4.3.4.2-BANDWIDTH"
        assert parsed["severity"] == "error"
        assert parsed["message"] == "test error"

    def test_includes_rendition(self) -> None:
        import sys
        from io import StringIO

        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_finding_json(_make_finding(), rendition_alias="video-720p")
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        assert parsed["rendition"] == "video-720p"

    def test_includes_timestamp(self) -> None:
        import sys
        from io import StringIO

        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_finding_json(_make_finding())
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        assert "timestamp" in parsed

    def test_optional_fields_included(self) -> None:
        import sys
        from io import StringIO

        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_finding_json(
                _make_finding(line=10)
            )
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        assert parsed["spec_ref"] == "RFC 8216 §4.3.4.2"
        assert parsed["line"] == 10

    def test_sorted_keys(self) -> None:
        import sys
        from io import StringIO

        old_stdout = sys.stdout
        sys.stdout = StringIO()
        try:
            print_finding_json(_make_finding())
            output = sys.stdout.getvalue().strip()
        finally:
            sys.stdout = old_stdout
        parsed = json.loads(output)
        keys = list(parsed.keys())
        assert keys == sorted(keys)

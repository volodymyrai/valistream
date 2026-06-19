"""Tests for findings.jsonl append-only writer."""

from __future__ import annotations

import json
from pathlib import Path

from valistream.artifacts.findings_log import append_finding
from valistream.validator.finding import Finding, FindingCode, Severity


def _make_finding(
    code: FindingCode = FindingCode.RFC8216_4_3_3_1,
    severity: Severity = Severity.ERROR,
    message: str = "test finding",
    **kwargs: object,
) -> Finding:
    return Finding(code=code, severity=severity, message=message, **kwargs)


class TestAppendFinding:
    def test_creates_file_if_not_exists(self, tmp_path: Path) -> None:
        log_path = tmp_path / "findings.jsonl"
        append_finding(log_path, _make_finding())
        assert log_path.exists()

    def test_one_finding_per_line(self, tmp_path: Path) -> None:
        log_path = tmp_path / "findings.jsonl"
        append_finding(log_path, _make_finding(message="first"))
        append_finding(log_path, _make_finding(message="second"))
        lines = log_path.read_text(encoding="utf-8").strip().split("\n")
        assert len(lines) == 2

    def test_valid_json_per_line(self, tmp_path: Path) -> None:
        log_path = tmp_path / "findings.jsonl"
        append_finding(log_path, _make_finding())
        line = log_path.read_text(encoding="utf-8").strip()
        parsed = json.loads(line)
        assert parsed["code"] == FindingCode.RFC8216_4_3_3_1.value
        assert parsed["severity"] == "error"
        assert parsed["message"] == "test finding"

    def test_includes_optional_fields_when_set(self, tmp_path: Path) -> None:
        log_path = tmp_path / "findings.jsonl"
        f = _make_finding(
            playlist_url="https://cdn.example.com/media.m3u8",
            line=42,
        )
        append_finding(log_path, f)
        parsed = json.loads(log_path.read_text(encoding="utf-8").strip())
        assert parsed["spec_ref"] == "RFC 8216 §4.3.3.1"
        assert parsed["playlist_url"] == "https://cdn.example.com/media.m3u8"
        assert parsed["line"] == 42

    def test_excludes_optional_fields_when_none(self, tmp_path: Path) -> None:
        log_path = tmp_path / "findings.jsonl"
        append_finding(log_path, _make_finding(code=FindingCode.DELIVERY_CONTENT_TYPE))
        parsed = json.loads(log_path.read_text(encoding="utf-8").strip())
        assert "spec_ref" not in parsed
        assert "playlist_url" not in parsed
        assert "line" not in parsed
        assert "details" not in parsed

    def test_sorted_keys(self, tmp_path: Path) -> None:
        log_path = tmp_path / "findings.jsonl"
        append_finding(log_path, _make_finding())
        line = log_path.read_text(encoding="utf-8").strip()
        keys = list(json.loads(line).keys())
        assert keys == sorted(keys)

    def test_includes_details_when_present(self, tmp_path: Path) -> None:
        log_path = tmp_path / "findings.jsonl"
        f = _make_finding(details={"expected": 6.0, "actual": 12.0})
        append_finding(log_path, f)
        parsed = json.loads(log_path.read_text(encoding="utf-8").strip())
        assert parsed["details"] == {"expected": 6.0, "actual": 12.0}

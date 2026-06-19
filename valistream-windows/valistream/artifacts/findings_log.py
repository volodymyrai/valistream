"""Append-only findings.jsonl writer."""

from __future__ import annotations

import json
import threading
from pathlib import Path

from valistream.validator.finding import Finding

_write_lock = threading.Lock()


def _finding_to_dict(finding: Finding) -> dict[str, object]:
    d: dict[str, object] = {
        "code": finding.code.value,
        "severity": finding.severity.value,
        "message": finding.message,
    }
    if finding.spec_ref is not None:
        d["spec_ref"] = finding.spec_ref
    if finding.playlist_url is not None:
        d["playlist_url"] = finding.playlist_url
    if finding.line is not None:
        d["line"] = finding.line
    if finding.details:
        d["details"] = finding.details
    return d


def append_finding(log_path: Path, finding: Finding) -> None:
    line = json.dumps(_finding_to_dict(finding), sort_keys=True, ensure_ascii=False)
    with _write_lock:
        with log_path.open("a", encoding="utf-8", newline="\n") as f:
            f.write(line + "\n")

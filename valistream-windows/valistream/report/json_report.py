"""report.json generator — machine-readable findings (schema v1)."""

from __future__ import annotations

import json
from pathlib import Path

from valistream.monitor.session import SessionState
from valistream.validator.finding import Finding, Severity


def _finding_record(finding: Finding) -> dict[str, object]:
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


def _rendition_info(rendition: object) -> dict[str, object]:
    d: dict[str, object] = {
        "uri": rendition.uri,  # type: ignore[union-attr]
        "bandwidth": rendition.bandwidth,  # type: ignore[union-attr]
    }
    alias = getattr(rendition, "alias", None)
    if alias:
        d["alias"] = alias
    res = getattr(rendition, "resolution", None)
    if res:
        d["resolution"] = res
    codecs = getattr(rendition, "codecs", None)
    if codecs:
        d["codecs"] = codecs
    avg_bw = getattr(rendition, "average_bandwidth", None)
    if avg_bw is not None:
        d["average_bandwidth"] = avg_bw
    return d


def _summary(findings: list[Finding]) -> dict[str, object]:
    counts: dict[str, int] = {"error": 0, "warning": 0, "info": 0}
    for f in findings:
        counts[f.severity.value] = counts.get(f.severity.value, 0) + 1
    return {
        "total": len(findings),
        "counts_by_severity": counts,
    }


def _iso(dt: object) -> str | None:
    if dt is None:
        return None
    return dt.isoformat()  # type: ignore[union-attr]


def build_report_dict(session: SessionState) -> dict[str, object]:
    started = session.started_at
    ended = session.ended_at
    duration_s: float | None = None
    if started and ended:
        duration_s = round((ended - started).total_seconds(), 3)

    state = "completed"
    if session.cancelled:
        state = "cancelled"
    elif ended is None:
        state = "in_progress"

    return {
        "schema_version": 1,
        "session": {
            "id": session.session_id,
            "url": session.url,
            "started_at": _iso(started),
            "ended_at": _iso(ended),
            "duration_s": duration_s,
            "state": state,
        },
        "stream": {
            "kind": session.stream_type.value if session.stream_type else None,
        },
        "findings": [_finding_record(f) for f in session.findings],
        "renditions": [_rendition_info(r) for r in session.selected_renditions],
        "summary": _summary(session.findings),
    }


def generate_json_report(session: SessionState, output_path: Path) -> None:
    report = build_report_dict(session)
    text = json.dumps(report, indent=2, sort_keys=False, ensure_ascii=False)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text + "\n", encoding="utf-8", newline="\n")

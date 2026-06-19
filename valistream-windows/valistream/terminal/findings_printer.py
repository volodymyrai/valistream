"""Colored findings output to the terminal."""

from __future__ import annotations

import json
from datetime import datetime, timezone

from rich.console import Console

from valistream.validator.finding import Finding, Severity

_SEVERITY_STYLES = {
    Severity.ERROR: "bold red",
    Severity.WARNING: "yellow",
    Severity.INFO: "blue",
}

_SEVERITY_LABELS = {
    Severity.ERROR: "ERROR",
    Severity.WARNING: "WARNING",
    Severity.INFO: "INFO",
}


def print_finding(console: Console, finding: Finding, *, rendition_alias: str | None = None) -> None:
    """Print a single finding with color-coded severity."""
    label = _SEVERITY_LABELS[finding.severity]
    style = _SEVERITY_STYLES[finding.severity]
    timestamp = datetime.now(timezone.utc).strftime("%H:%M:%S")

    parts = [f"[{style}][{label}][/{style}]", f"{finding.code.value}", "—", finding.message]
    context_parts: list[str] = []
    if rendition_alias:
        context_parts.append(f"rendition: {rendition_alias}")
    context_parts.append(f"at: {timestamp}")

    msg = " ".join(parts) + f" ({', '.join(context_parts)})"
    console.print(msg, highlight=False)


def print_finding_json(finding: Finding, *, rendition_alias: str | None = None) -> None:
    """Print a finding as a JSON line to stdout."""
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
    if rendition_alias is not None:
        d["rendition"] = rendition_alias
    d["timestamp"] = datetime.now(timezone.utc).isoformat()
    print(json.dumps(d, sort_keys=True, ensure_ascii=False), flush=True)

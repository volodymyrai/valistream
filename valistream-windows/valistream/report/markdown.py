"""report.md generator — human-readable session report."""

from __future__ import annotations

from pathlib import Path

from valistream.monitor.session import SessionState
from valistream.validator.finding import Finding, Severity


def _iso(dt: object) -> str:
    if dt is None:
        return "—"
    return dt.isoformat()  # type: ignore[union-attr]


def _severity_icon(severity: Severity) -> str:
    return {"error": "ERROR", "warning": "WARNING", "info": "INFO"}[severity.value]


def _format_finding(f: Finding) -> str:
    spec = f" ({f.spec_ref})" if f.spec_ref else ""
    line = f"- **[{_severity_icon(f.severity)}]** `{f.code.value}`{spec} — {f.message}"
    if f.playlist_url:
        line += f" *(playlist: {f.playlist_url})*"
    return line


def _findings_section(findings: list[Finding], severity: Severity) -> list[str]:
    matched = [f for f in findings if f.severity == severity]
    if not matched:
        return []
    lines = [f"### {severity.value.upper()}S ({len(matched)})", ""]
    for f in matched:
        lines.append(_format_finding(f))
    lines.append("")
    return lines


def build_markdown(session: SessionState) -> str:
    lines: list[str] = []

    # Session header
    lines.append("# Valistream Report")
    lines.append("")
    lines.append(f"| Field | Value |")
    lines.append(f"|-------|-------|")
    lines.append(f"| Session ID | `{session.session_id}` |")
    lines.append(f"| URL | {session.url} |")
    lines.append(f"| Started | {_iso(session.started_at)} |")
    lines.append(f"| Ended | {_iso(session.ended_at)} |")

    if session.started_at and session.ended_at:
        dur = (session.ended_at - session.started_at).total_seconds()
        lines.append(f"| Duration | {dur:.1f}s |")

    state = "completed"
    if session.cancelled:
        state = "cancelled"
    elif session.ended_at is None:
        state = "in progress"
    lines.append(f"| State | {state} |")
    lines.append("")

    # Stream info
    lines.append("## Stream Info")
    lines.append("")
    kind = session.stream_type.value.upper() if session.stream_type else "UNKNOWN"
    lines.append(f"- **Type:** {kind}")
    lines.append(f"- **Renditions selected:** {len(session.selected_renditions)}")
    lines.append("")

    # Findings by severity
    error_count = sum(1 for f in session.findings if f.severity == Severity.ERROR)
    warning_count = sum(1 for f in session.findings if f.severity == Severity.WARNING)
    info_count = sum(1 for f in session.findings if f.severity == Severity.INFO)

    lines.append("## Findings Summary")
    lines.append("")
    lines.append(f"| Severity | Count |")
    lines.append(f"|----------|-------|")
    lines.append(f"| Error | {error_count} |")
    lines.append(f"| Warning | {warning_count} |")
    lines.append(f"| Info | {info_count} |")
    lines.append(f"| **Total** | **{len(session.findings)}** |")
    lines.append("")

    # Findings details grouped by severity
    if session.findings:
        lines.append("## Findings")
        lines.append("")
        for sev in (Severity.ERROR, Severity.WARNING, Severity.INFO):
            lines.extend(_findings_section(session.findings, sev))

    # Rendition summary table
    if session.selected_renditions:
        lines.append("## Renditions")
        lines.append("")
        lines.append("| Alias | Resolution | Bandwidth | Codecs |")
        lines.append("|-------|------------|-----------|--------|")
        for r in session.selected_renditions:
            alias = getattr(r, "alias", r.uri)
            res = getattr(r, "resolution", None) or "—"
            bw = getattr(r, "bandwidth", 0)
            codecs = getattr(r, "codecs", None) or "—"
            lines.append(f"| {alias} | {res} | {bw} | {codecs} |")
        lines.append("")

    # Legend
    if session.selected_renditions:
        lines.append("## Legend")
        lines.append("")
        for r in session.selected_renditions:
            alias = getattr(r, "alias", r.uri)
            lines.append(f"- **{alias}**: `{r.uri}`")
        lines.append("")

    return "\n".join(lines)


def generate_markdown_report(session: SessionState, output_path: Path) -> None:
    md = build_markdown(session)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(md, encoding="utf-8", newline="\n")

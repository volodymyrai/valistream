"""Session summary output at session end."""

from __future__ import annotations

import json

from rich.console import Console
from rich.table import Table

from valistream.monitor.session import SessionState
from valistream.validator.finding import Severity


def print_summary(console: Console, session: SessionState) -> None:
    """Print a summary table of the session."""
    duration = _format_duration(session)

    error_count = sum(1 for f in session.findings if f.severity == Severity.ERROR)
    warning_count = sum(1 for f in session.findings if f.severity == Severity.WARNING)
    info_count = sum(1 for f in session.findings if f.severity == Severity.INFO)

    console.print()
    console.rule("[bold]Session Summary[/bold]")
    console.print()

    table = Table(show_header=False, box=None, padding=(0, 2))
    table.add_column("Key", style="bold")
    table.add_column("Value")

    table.add_row("Duration", duration)
    table.add_row("Total Findings", str(len(session.findings)))
    table.add_row("Errors", f"[red]{error_count}[/red]")
    table.add_row("Warnings", f"[yellow]{warning_count}[/yellow]")
    table.add_row("Info", f"[blue]{info_count}[/blue]")

    if session.output_dir:
        table.add_row("Output", str(session.output_dir))

    console.print(table)
    console.print()


def print_summary_json(session: SessionState) -> None:
    """Print the session summary as a JSON line to stdout."""
    duration_s = 0.0
    if session.ended_at and session.started_at:
        duration_s = (session.ended_at - session.started_at).total_seconds()

    error_count = sum(1 for f in session.findings if f.severity == Severity.ERROR)
    warning_count = sum(1 for f in session.findings if f.severity == Severity.WARNING)
    info_count = sum(1 for f in session.findings if f.severity == Severity.INFO)

    state = "in_progress"
    if session.ended_at:
        state = "cancelled" if session.cancelled else "completed"

    d: dict[str, object] = {
        "type": "summary",
        "session_id": session.session_id,
        "state": state,
        "duration_s": duration_s,
        "total_findings": len(session.findings),
        "errors": error_count,
        "warnings": warning_count,
        "infos": info_count,
    }
    if session.output_dir:
        d["output_dir"] = str(session.output_dir)

    print(json.dumps(d, sort_keys=True, ensure_ascii=False), flush=True)


def _format_duration(session: SessionState) -> str:
    if session.ended_at is None or session.started_at is None:
        return "in progress"
    delta = (session.ended_at - session.started_at).total_seconds()
    if delta < 60:
        return f"{delta:.1f}s"
    minutes = int(delta // 60)
    seconds = delta % 60
    return f"{minutes}m {seconds:.0f}s"

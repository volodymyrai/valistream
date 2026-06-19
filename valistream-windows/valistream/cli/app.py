"""Click CLI — orchestrates fetch, parse, validate, monitor, and report."""

from __future__ import annotations

import asyncio
import signal
import sys
from pathlib import Path

import click
from rich.console import Console

from valistream import __version__


@click.command(context_settings={"help_option_names": ["-h", "--help"]})
@click.argument("url")
@click.option(
    "--limit",
    default=None,
    help="Live session time limit (e.g. 90s, 15m, 24h).",
)
@click.option(
    "--preselect",
    default=None,
    help="Pre-select renditions (comma-separated patterns matching ID, group, name, or URL).",
)
@click.option(
    "--select",
    is_flag=True,
    default=False,
    help="Interactive multi-select checklist (TTY required; all pre-selected).",
)
@click.option(
    "--non-interactive",
    is_flag=True,
    default=False,
    help="Never prompt; process all renditions.",
)
@click.option(
    "--output-dir",
    default=None,
    type=click.Path(),
    help="Parent directory for session folders (default: ~/.valistream/sessions/).",
)
@click.option(
    "--json",
    "json_output",
    is_flag=True,
    default=False,
    help="Machine output: findings as JSON Lines on stdout.",
)
@click.option(
    "--quiet",
    is_flag=True,
    default=False,
    help="Suppress live status; findings and summary only.",
)
@click.option(
    "--verbose",
    is_flag=True,
    default=False,
    help="Extended detail: raw timestamps, all HTTP headers.",
)
@click.option(
    "--no-color",
    is_flag=True,
    default=False,
    help="Disable terminal color output (also honored via NO_COLOR env var).",
)
@click.version_option(version=__version__, prog_name="valistream")
def main(
    url: str,
    limit: str | None,
    preselect: str | None,
    select: bool,
    non_interactive: bool,
    output_dir: str | None,
    json_output: bool,
    quiet: bool,
    verbose: bool,
    no_color: bool,
) -> None:
    """Validate and monitor HLS playlists against RFC 8216 and Apple HLS authoring rules.

    URL is an HTTP/HTTPS URL of a master or media playlist (auto-detected).
    """
    from valistream.cli.time_limit import parse_time_limit
    from valistream.terminal.color import init_color, should_use_color

    use_color = should_use_color(no_color)
    init_color(use_color)
    console = Console(no_color=not use_color, stderr=True)

    limit_seconds: float | None = None
    if limit is not None:
        try:
            limit_seconds = parse_time_limit(limit)
        except ValueError as exc:
            console.print(f"[red]Error:[/red] {exc}", highlight=False)
            sys.exit(2)

    try:
        exit_code = asyncio.run(
            _run(
                url=url,
                limit_seconds=limit_seconds,
                preselect=preselect,
                select=select,
                non_interactive=non_interactive,
                output_dir=output_dir,
                json_output=json_output,
                quiet=quiet,
                verbose=verbose,
                console=console,
            )
        )
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted.[/yellow]", highlight=False)
        exit_code = 130

    sys.exit(exit_code)


async def _run(
    *,
    url: str,
    limit_seconds: float | None,
    preselect: str | None,
    select: bool,
    non_interactive: bool,
    output_dir: str | None,
    json_output: bool,
    quiet: bool,
    verbose: bool,
    console: Console,
) -> int:
    from valistream.artifacts.findings_log import append_finding
    from valistream.cli.preselect import filter_renditions
    from valistream.fetch.client import HLSClient
    from valistream.monitor.live import monitor_live
    from valistream.monitor.session import (
        SessionState,
        classify_stream,
        make_session_id,
        select_renditions,
    )
    from valistream.monitor.vod import validate_vod
    from valistream.parser.master import parse_master_playlist
    from valistream.parser.media import parse_media_playlist
    from valistream.parser.models import ParseError, StreamType
    from valistream.report.json_report import generate_json_report
    from valistream.report.markdown import generate_markdown_report
    from valistream.terminal.display import create_live_display
    from valistream.terminal.findings_printer import print_finding, print_finding_json
    from valistream.terminal.selector import select_renditions_interactive
    from valistream.terminal.summary import print_summary, print_summary_json
    from valistream.validator.content_type import validate_content_type
    from valistream.validator.engine import validate_media

    async with HLSClient() as client:
        if not quiet and not json_output:
            console.print(f"[bold]valistream {__version__}[/bold]", highlight=False)
            console.print(f"Fetching [cyan]{url}[/cyan]…", highlight=False)

        result = await client.fetch(url)

        if not result.ok:
            console.print(
                f"[red]Error:[/red] Failed to fetch playlist (HTTP {result.status_code})",
                highlight=False,
            )
            return 1

        if verbose and not json_output:
            console.print(f"  Status: {result.status_code}  ({result.response_time_ms:.0f}ms)", highlight=False)
            for k, v in result.headers.items():
                console.print(f"  {k}: {v}", highlight=False)

        ct = result.headers.get("Content-Type", "")
        stream_type = classify_stream(result.body)
        session_id = make_session_id(url)

        base_dir = Path(output_dir) if output_dir else Path.home() / ".valistream" / "sessions"
        session_dir = base_dir / session_id
        session_dir.mkdir(parents=True, exist_ok=True)

        session = SessionState(
            session_id=session_id,
            url=url,
            output_dir=session_dir,
            stream_type=stream_type,
        )

        if ct:
            session.add_findings(validate_content_type(ct, playlist_url=url))

        master = parse_master_playlist(result.body, url)

        if isinstance(master, ParseError):
            media = parse_media_playlist(result.body, url)
            if isinstance(media, ParseError):
                console.print(
                    f"[red]Error:[/red] Could not parse playlist: {master.message}",
                    highlight=False,
                )
                return 1

            session.stream_type = StreamType.VOD
            session.add_findings(validate_media(media))
            session.finish()
        else:
            renditions = list(master.variants)

            if preselect:
                renditions = filter_renditions(preselect, renditions)
            elif select and not non_interactive:
                renditions = select_renditions_interactive(renditions)

            if not renditions:
                console.print("[yellow]No renditions matched.[/yellow]", highlight=False)
                return 1

            session.selected_renditions = renditions

            if not quiet and not json_output:
                console.print(
                    f"\n[bold]{stream_type.value.upper()}[/bold] stream — "
                    f"{len(renditions)} rendition(s) selected",
                    highlight=False,
                )
                for r in renditions:
                    console.print(f"  • {r.alias}", highlight=False)
                console.print()

            if stream_type == StreamType.VOD:
                await validate_vod(session, master, client)
            else:
                await monitor_live(
                    session, master, client, limit_seconds=limit_seconds
                )

        findings_log = session_dir / "findings.jsonl"
        for finding in session.findings:
            append_finding(findings_log, finding)
            if json_output:
                print_finding_json(finding)
            elif not quiet:
                print_finding(console, finding)

        generate_json_report(session, session_dir / "report.json")
        generate_markdown_report(session, session_dir / "report.md")

        if json_output:
            print_summary_json(session)
        elif not quiet:
            print_summary(console, session)
            console.print(f"Output: [cyan]{session_dir}[/cyan]", highlight=False)

    error_count = sum(1 for f in session.findings if f.severity.value == "error")
    return 1 if error_count > 0 else 0

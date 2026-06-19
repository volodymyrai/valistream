"""rich-based live status panel for terminal output."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import TYPE_CHECKING

from rich.console import Console
from rich.live import Live
from rich.table import Table

if TYPE_CHECKING:
    from valistream.parser.models import Rendition


class RenditionStatus:
    """Mutable status for one rendition in the live panel."""

    __slots__ = ("alias", "refresh_count", "last_sequence", "finding_count", "last_fetch")

    def __init__(self, alias: str) -> None:
        self.alias = alias
        self.refresh_count: int = 0
        self.last_sequence: int | None = None
        self.finding_count: int = 0
        self.last_fetch: datetime | None = None

    def update(
        self,
        *,
        sequence: int | None = None,
        new_findings: int = 0,
    ) -> None:
        self.refresh_count += 1
        if sequence is not None:
            self.last_sequence = sequence
        self.finding_count += new_findings
        self.last_fetch = datetime.now(timezone.utc)


class LiveDisplay:
    """Live-updating status panel using rich.Live."""

    def __init__(self, console: Console) -> None:
        self._console = console
        self._statuses: dict[str, RenditionStatus] = {}
        self._live: Live | None = None

    def add_rendition(self, rendition: Rendition) -> RenditionStatus:
        status = RenditionStatus(rendition.alias)
        self._statuses[rendition.alias] = status
        return status

    def get_status(self, alias: str) -> RenditionStatus | None:
        return self._statuses.get(alias)

    def _build_table(self) -> Table:
        table = Table(title="Rendition Status", expand=True)
        table.add_column("Rendition", style="cyan", no_wrap=True)
        table.add_column("Refreshes", justify="right")
        table.add_column("Last Seq", justify="right")
        table.add_column("Findings", justify="right")
        table.add_column("Last Fetch", no_wrap=True)

        for status in self._statuses.values():
            seq = str(status.last_sequence) if status.last_sequence is not None else "-"
            fetch = status.last_fetch.strftime("%H:%M:%S") if status.last_fetch else "-"
            findings_style = "red" if status.finding_count > 0 else "green"
            table.add_row(
                status.alias,
                str(status.refresh_count),
                seq,
                f"[{findings_style}]{status.finding_count}[/{findings_style}]",
                fetch,
            )
        return table

    def refresh(self) -> None:
        if self._live is not None:
            self._live.update(self._build_table())

    def start(self) -> None:
        self._live = Live(
            self._build_table(),
            console=self._console,
            refresh_per_second=4,
        )
        self._live.start()

    def stop(self) -> None:
        if self._live is not None:
            self._live.stop()
            self._live = None

    def __enter__(self) -> LiveDisplay:
        self.start()
        return self

    def __exit__(self, *args: object) -> None:
        self.stop()


def create_live_display(console: Console | None = None) -> LiveDisplay:
    """Create a LiveDisplay for monitoring status."""
    if console is None:
        console = Console()
    return LiveDisplay(console)

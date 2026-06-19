"""Live refresh loop — scheduling, limit enforcement, cancellation."""

from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING, Protocol, runtime_checkable

from valistream.parser.models import MasterPlaylist, MediaPlaylist, ParseError
from valistream.parser.media import parse_media_playlist
from valistream.parser.url import resolve_playlist_url
from valistream.validator.content_type import validate_content_type
from valistream.validator.continuity import check_continuity
from valistream.validator.engine import validate_master, validate_media
from valistream.validator.finding import Finding, FindingCode, Severity
from valistream.monitor.session import SessionState

if TYPE_CHECKING:
    from valistream.terminal.display import LiveDisplay, RenditionStatus


@runtime_checkable
class FetcherProtocol(Protocol):
    async def fetch(self, url: str) -> object: ...


async def monitor_live(
    session: SessionState,
    master: MasterPlaylist,
    client: object,
    *,
    limit_seconds: float | None = None,
    display: LiveDisplay | None = None,
) -> None:
    session.add_findings(validate_master(master))

    try:
        with display or _NullContext():
            if display is not None:
                for rendition in session.selected_renditions:
                    display.add_rendition(rendition)

            if limit_seconds is not None:
                await asyncio.wait_for(
                    _monitor_all_renditions(session, master, client, display=display),
                    timeout=limit_seconds,
                )
            else:
                await _monitor_all_renditions(session, master, client, display=display)
    except asyncio.TimeoutError:
        pass
    except asyncio.CancelledError:
        session.cancelled = True
    finally:
        session.finish()


class _NullContext:
    def __enter__(self) -> _NullContext:
        return self

    def __exit__(self, *args: object) -> None:
        pass


async def _monitor_all_renditions(
    session: SessionState,
    master: MasterPlaylist,
    client: object,
    *,
    display: LiveDisplay | None = None,
) -> None:
    async with asyncio.TaskGroup() as tg:
        for rendition in session.selected_renditions:
            status = display.get_status(rendition.alias) if display is not None else None
            tg.create_task(
                _monitor_rendition(session, master, rendition, client, status=status, display=display)
            )


async def _monitor_rendition(
    session: SessionState,
    master: MasterPlaylist,
    rendition: object,
    client: object,
    *,
    status: RenditionStatus | None = None,
    display: LiveDisplay | None = None,
) -> None:
    url = rendition.uri  # type: ignore[union-attr]
    if not url.startswith("http"):
        url = resolve_playlist_url(master.url, url)

    result = await client.fetch(url)  # type: ignore[union-attr]
    if not result.ok:  # type: ignore[union-attr]
        async with session.lock:
            session.add_finding(Finding(
                code=FindingCode.TOOL_FETCH_VARIANT,
                severity=Severity.ERROR,
                message=f"HTTP {result.status_code}: could not fetch variant playlist",  # type: ignore[union-attr]
                playlist_url=url,
            ))
        return

    ct = result.headers.get("Content-Type", "")  # type: ignore[union-attr]
    if ct:
        async with session.lock:
            session.add_findings(validate_content_type(ct, playlist_url=url))

    parsed = parse_media_playlist(result.body, url)  # type: ignore[union-attr]
    if isinstance(parsed, ParseError):
        return

    new_findings: list = []
    async with session.lock:
        new_findings = validate_media(parsed)
        session.add_findings(new_findings)

    if status is not None:
        status.update(sequence=getattr(parsed, "media_sequence", None), new_findings=len(new_findings))
    if display is not None:
        display.refresh()

    previous: MediaPlaylist = parsed

    while True:
        if previous.is_endlist:
            break
        if session.cancelled:
            break

        target = previous.target_duration or 6.0
        delay = target / 2.0

        try:
            await asyncio.sleep(delay)
        except asyncio.CancelledError:
            break

        if session.cancelled:
            break

        result = await client.fetch(url)  # type: ignore[union-attr]
        if not result.ok:  # type: ignore[union-attr]
            continue

        parsed = parse_media_playlist(result.body, url)  # type: ignore[union-attr]
        if isinstance(parsed, ParseError):
            continue

        new_findings = []
        async with session.lock:
            media_findings = validate_media(parsed)
            continuity_findings = check_continuity(previous, parsed)
            new_findings = media_findings + continuity_findings
            session.add_findings(new_findings)

        if status is not None:
            status.update(sequence=getattr(parsed, "media_sequence", None), new_findings=len(new_findings))
        if display is not None:
            display.refresh()

        previous = parsed

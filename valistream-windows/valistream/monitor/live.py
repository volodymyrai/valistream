"""Live refresh loop — scheduling, limit enforcement, cancellation."""

from __future__ import annotations

import asyncio
from typing import Protocol, runtime_checkable

from valistream.parser.models import MasterPlaylist, MediaPlaylist, ParseError
from valistream.parser.media import parse_media_playlist
from valistream.parser.url import resolve_playlist_url
from valistream.validator.content_type import validate_content_type
from valistream.validator.continuity import check_continuity
from valistream.validator.engine import validate_master, validate_media
from valistream.monitor.session import SessionState


@runtime_checkable
class FetcherProtocol(Protocol):
    async def fetch(self, url: str) -> object: ...


async def monitor_live(
    session: SessionState,
    master: MasterPlaylist,
    client: object,
    *,
    limit_seconds: float | None = None,
) -> None:
    session.add_findings(validate_master(master))

    try:
        if limit_seconds is not None:
            await asyncio.wait_for(
                _monitor_all_renditions(session, master, client),
                timeout=limit_seconds,
            )
        else:
            await _monitor_all_renditions(session, master, client)
    except asyncio.TimeoutError:
        pass
    except asyncio.CancelledError:
        session.cancelled = True
    finally:
        session.finish()


async def _monitor_all_renditions(
    session: SessionState,
    master: MasterPlaylist,
    client: object,
) -> None:
    async with asyncio.TaskGroup() as tg:
        for rendition in session.selected_renditions:
            tg.create_task(
                _monitor_rendition(session, master, rendition, client)
            )


async def _monitor_rendition(
    session: SessionState,
    master: MasterPlaylist,
    rendition: object,
    client: object,
) -> None:
    url = rendition.uri  # type: ignore[union-attr]
    if not url.startswith("http"):
        url = resolve_playlist_url(master.url, url)

    result = await client.fetch(url)  # type: ignore[union-attr]
    if not result.ok:  # type: ignore[union-attr]
        return

    ct = result.headers.get("Content-Type", "")  # type: ignore[union-attr]
    if ct:
        async with session.lock:
            session.add_findings(validate_content_type(ct, playlist_url=url))

    parsed = parse_media_playlist(result.body, url)  # type: ignore[union-attr]
    if isinstance(parsed, ParseError):
        return

    async with session.lock:
        session.add_findings(validate_media(parsed))

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

        async with session.lock:
            session.add_findings(validate_media(parsed))
            session.add_findings(check_continuity(previous, parsed))

        previous = parsed

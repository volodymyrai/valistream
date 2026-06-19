"""VOD single-pass validation logic."""

from __future__ import annotations

from typing import Protocol

from valistream.parser.models import MasterPlaylist, MediaPlaylist, ParseError, Rendition
from valistream.parser.media import parse_media_playlist
from valistream.parser.url import resolve_playlist_url
from valistream.validator.content_type import validate_content_type
from valistream.validator.engine import validate_master, validate_media
from valistream.monitor.session import SessionState


class Fetcher(Protocol):
    async def fetch(self, url: str) -> FetchLike: ...


class FetchLike(Protocol):
    @property
    def url(self) -> str: ...
    @property
    def status_code(self) -> int: ...
    @property
    def body(self) -> str: ...
    @property
    def headers(self) -> dict[str, str]: ...
    @property
    def ok(self) -> bool: ...


async def validate_vod(
    session: SessionState,
    master: MasterPlaylist,
    client: object,
) -> None:
    session.add_findings(validate_master(master))

    for rendition in session.selected_renditions:
        url = rendition.uri
        if not url.startswith("http"):
            url = resolve_playlist_url(master.url, url)

        result = await client.fetch(url)  # type: ignore[union-attr]

        if not result.ok:
            continue

        ct = result.headers.get("Content-Type", "")
        if ct:
            session.add_findings(validate_content_type(ct, playlist_url=url))

        parsed = parse_media_playlist(result.body, url)
        if isinstance(parsed, ParseError):
            continue

        session.add_findings(validate_media(parsed))

    session.finish()

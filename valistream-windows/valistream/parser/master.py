"""Master playlist parsing → MasterPlaylist model."""

from __future__ import annotations

import m3u8

from valistream.parser.models import MasterPlaylist, ParseError, Rendition
from valistream.parser.url import resolve_playlist_url


def parse_master_playlist(
    body: str,
    url: str,
) -> MasterPlaylist | ParseError:
    """Parse a master playlist body into a MasterPlaylist."""
    try:
        obj = m3u8.loads(body)
    except Exception as exc:
        return ParseError(message=str(exc), url=url)

    if not obj.is_variant:
        return ParseError(message="Not a master playlist (no variant streams found)", url=url)

    variants: list[Rendition] = []
    for pl in obj.playlists:
        si = pl.stream_info
        res = f"{si.resolution[0]}x{si.resolution[1]}" if si.resolution else None
        uri = resolve_playlist_url(url, pl.uri) if pl.uri else pl.uri

        variants.append(
            Rendition(
                uri=uri,
                bandwidth=si.bandwidth or 0,
                resolution=res,
                codecs=si.codecs,
                audio=si.audio,
                subtitles=si.subtitles,
                video=si.video if hasattr(si, "video") else None,
                closed_captions=si.closed_captions if hasattr(si, "closed_captions") else None,
                average_bandwidth=getattr(si, "average_bandwidth", None),
                frame_rate=getattr(si, "frame_rate", None),
            )
        )

    media_renditions: list[Rendition] = []
    for md in obj.media:
        uri = resolve_playlist_url(url, md.uri) if md.uri else ""

        media_renditions.append(
            Rendition(
                uri=uri,
                name=md.name,
                type=md.type,
                group_id=md.group_id,
                language=md.language,
                default=md.default == "YES",
                autoselect=getattr(md, "autoselect", None) == "YES",
                forced=getattr(md, "forced", None) == "YES",
            )
        )

    return MasterPlaylist(
        url=url,
        version=obj.version,
        variants=variants,
        media=media_renditions,
        is_independent_segments=obj.is_independent_segments,
    )

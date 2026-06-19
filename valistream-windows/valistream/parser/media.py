"""Media playlist parsing → MediaPlaylist model."""

from __future__ import annotations

import m3u8

from valistream.parser.models import MediaPlaylist, ParseError, Segment
from valistream.parser.url import resolve_playlist_url


def parse_media_playlist(
    body: str,
    url: str,
) -> MediaPlaylist | ParseError:
    """Parse a media playlist body into a MediaPlaylist."""
    try:
        obj = m3u8.loads(body)
    except Exception as exc:
        return ParseError(message=str(exc), url=url)

    if obj.is_variant:
        return ParseError(message="Expected media playlist but got master playlist", url=url)

    segments: list[Segment] = []
    for seg in obj.segments:
        seg_uri = resolve_playlist_url(url, seg.uri) if seg.uri else seg.uri

        key_dict: dict[str, str] | None = None
        if seg.key and seg.key.method and seg.key.method != "NONE":
            key_dict = {"METHOD": seg.key.method}
            if seg.key.uri:
                key_dict["URI"] = seg.key.uri
            if seg.key.iv:
                key_dict["IV"] = seg.key.iv

        map_dict: dict[str, str] | None = None
        if seg.init_section:
            map_uri = seg.init_section.uri or ""
            map_dict = {"URI": resolve_playlist_url(url, map_uri)}
            if seg.init_section.byterange:
                map_dict["BYTERANGE"] = seg.init_section.byterange

        pdt = str(seg.program_date_time) if seg.program_date_time else None

        segments.append(
            Segment(
                uri=seg_uri,
                duration=float(seg.duration),
                title=seg.title if seg.title else None,
                byterange=seg.byterange,
                discontinuity=bool(seg.discontinuity),
                program_date_time=pdt,
                key=key_dict,
                map_info=map_dict,
            )
        )

    return MediaPlaylist(
        url=url,
        version=obj.version,
        target_duration=float(obj.target_duration) if obj.target_duration is not None else None,
        media_sequence=obj.media_sequence or 0,
        discontinuity_sequence=obj.discontinuity_sequence or 0,
        playlist_type=obj.playlist_type,
        is_endlist=obj.is_endlist,
        segments=segments,
        is_independent_segments=obj.is_independent_segments,
    )

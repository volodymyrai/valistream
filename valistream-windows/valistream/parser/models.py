"""Playlist data models — PlaylistType, Rendition, Segment, etc."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum


class PlaylistType(Enum):
    """Discriminator for master vs media playlists."""

    MASTER = "master"
    MEDIA = "media"


class StreamType(Enum):
    """Live vs VOD classification."""

    LIVE = "live"
    VOD = "vod"


@dataclass
class Rendition:
    """A variant stream or alternate rendition from a master playlist."""

    uri: str
    bandwidth: int = 0
    resolution: str | None = None
    codecs: str | None = None
    audio: str | None = None
    subtitles: str | None = None
    name: str | None = None
    group_id: str | None = None
    type: str | None = None
    language: str | None = None
    average_bandwidth: int | None = None
    frame_rate: float | None = None
    video: str | None = None
    closed_captions: str | None = None
    default: bool = False
    autoselect: bool = False
    forced: bool = False

    @property
    def alias(self) -> str:
        """Generate a stable human-readable alias for this rendition."""
        if self.type and self.type != "VIDEO":
            return _media_alias(self)
        return _variant_alias(self)


@dataclass
class Segment:
    """A media segment from a media playlist."""

    uri: str
    duration: float
    title: str | None = None
    byterange: str | None = None
    discontinuity: bool = False
    program_date_time: str | None = None
    key: dict[str, str] | None = None
    map_info: dict[str, str] | None = None


@dataclass
class MediaPlaylist:
    """Parsed media playlist."""

    url: str
    version: int | None = None
    target_duration: float | None = None
    media_sequence: int = 0
    discontinuity_sequence: int = 0
    playlist_type: str | None = None
    is_endlist: bool = False
    segments: list[Segment] = field(default_factory=list)
    is_independent_segments: bool = False


@dataclass
class MasterPlaylist:
    """Parsed master playlist."""

    url: str
    version: int | None = None
    variants: list[Rendition] = field(default_factory=list)
    media: list[Rendition] = field(default_factory=list)
    is_independent_segments: bool = False


@dataclass
class ParseError:
    """A non-fatal parse error captured instead of raising an exception."""

    message: str
    url: str
    line_number: int | None = None


_SLUG_RE = re.compile(r"[^a-z0-9]+")


def _slugify(text: str) -> str:
    return _SLUG_RE.sub("-", text.lower()).strip("-") or "unknown"


def _variant_alias(r: Rendition) -> str:
    parts: list[str] = ["video"]
    if r.resolution:
        height = r.resolution.split("x")[-1]
        parts.append(f"{height}p")
    elif r.bandwidth:
        parts.append(f"{r.bandwidth // 1000}k")
    return "-".join(parts) if len(parts) > 1 else f"video-{r.bandwidth}"


def _media_alias(r: Rendition) -> str:
    prefix = (r.type or "media").lower()
    if r.language:
        return f"{prefix}-{_slugify(r.language)}"
    if r.name:
        return f"{prefix}-{_slugify(r.name)}"
    if r.group_id:
        return f"{prefix}-{_slugify(r.group_id)}"
    return prefix

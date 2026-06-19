"""Finding, Severity, and FindingCode models."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from valistream.validator import spec_catalog


class Severity(str, Enum):
    ERROR = "error"
    WARNING = "warning"
    INFO = "info"


class FindingCode(str, Enum):
    # RFC 8216 — Media Playlist
    RFC8216_4_3_3_1 = "RFC8216.4.3.3.1"
    RFC8216_4_3_3_1_DURATION = "RFC8216.4.3.3.1-DURATION"
    RFC8216_4_3_3_DUPLICATE = "RFC8216.4.3.3-DUPLICATE"

    # RFC 8216 — Master Playlist
    RFC8216_4_3_1_1 = "RFC8216.4.3.1.1"
    RFC8216_4_3_4_2_BANDWIDTH = "RFC8216.4.3.4.2-BANDWIDTH"
    RFC8216_4_3_4_2_URI = "RFC8216.4.3.4.2-URI"
    RFC8216_4_3_4_1 = "RFC8216.4.3.4.1"
    RFC8216_4_3_4_2_1 = "RFC8216.4.3.4.2.1"

    # Apple HLS Authoring
    APPLE_CODECS = "APPLE.codecs"
    APPLE_AVERAGE_BANDWIDTH = "APPLE.average-bandwidth"
    APPLE_RESOLUTION = "APPLE.resolution"
    APPLE_VARIANT_LADDER = "APPLE.variant-ladder"
    APPLE_INDEPENDENT_SEGMENTS = "APPLE.independent-segments"
    APPLE_TARGET_DURATION = "APPLE.target-duration"
    APPLE_IFRAME_PLAYLISTS = "APPLE.iframe-playlists"

    # Continuity (live)
    CONTINUITY_MEDIA_SEQUENCE = "TOOL.continuity.media-sequence"
    CONTINUITY_HEAD_REMOVAL = "TOOL.continuity.head-removal"
    CONTINUITY_SEGMENT_STABILITY = "TOOL.continuity.segment-stability"
    CONTINUITY_DISCONTINUITY_SEQUENCE = "TOOL.continuity.discontinuity-sequence"
    CONTINUITY_DISCONTINUITY_INSERTED = "TOOL.continuity.discontinuity-inserted"

    # Delivery / transport
    DELIVERY_CONTENT_TYPE = "TOOL.delivery.content-type"


@dataclass(frozen=True)
class Finding:
    code: FindingCode
    severity: Severity
    message: str
    playlist_url: str | None = None
    line: int | None = None
    details: dict[str, object] = field(default_factory=dict)
    spec_ref: str | None = field(init=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "spec_ref", spec_catalog.reference(self.code.value))

"""Rule-to-spec citation catalog for findings grounded in an external specification."""

from __future__ import annotations

_RFC8216_PREFIX = "RFC8216."

_EXPLICIT: dict[str, str] = {
    "APPLE.codecs": "HLS Authoring §9.1",
    "APPLE.resolution": "HLS Authoring §9.2",
    "APPLE.independent-segments": "HLS Authoring §9.11",
    "APPLE.average-bandwidth": "HLS Authoring §9.14",
    "APPLE.iframe-playlists": "HLS Authoring §6.1",
    "TOOL.continuity.media-sequence": "RFC 8216 §6.2.2",
    "TOOL.continuity.head-removal": "RFC 8216 §6.2.2",
    "TOOL.continuity.segment-stability": "RFC 8216 §6.2.2",
    "TOOL.continuity.discontinuity-inserted": "RFC 8216 §4.3.2.3",
    "TOOL.continuity.discontinuity-sequence": "RFC 8216 §4.3.3.3",
    "TOOL.staleness": "RFC 8216 §6.2.1",
}


def reference(rule_id: str) -> str | None:
    if rule_id.startswith(_RFC8216_PREFIX):
        remainder = rule_id[len(_RFC8216_PREFIX):]
        dash = remainder.find("-")
        section = remainder[:dash] if dash != -1 else remainder
        if not section:
            return None
        return f"RFC 8216 §{section}"
    return _EXPLICIT.get(rule_id)

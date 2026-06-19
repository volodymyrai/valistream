"""HTTP Content-Type validation for HLS playlists."""

from __future__ import annotations

from valistream.validator.finding import Finding, FindingCode, Severity

VALID_CONTENT_TYPES = frozenset({
    "application/vnd.apple.mpegurl",
    "application/x-mpegurl",
    "audio/mpegurl",
    "audio/x-mpegurl",
})


def validate_content_type(content_type: str, playlist_url: str = "") -> list[Finding]:
    normalized = content_type.split(";")[0].strip().lower()
    if normalized in VALID_CONTENT_TYPES:
        return []
    return [Finding(
        code=FindingCode.DELIVERY_CONTENT_TYPE,
        severity=Severity.WARNING,
        message=f'Unexpected Content-Type "{content_type}"; expected application/vnd.apple.mpegurl.',
        playlist_url=playlist_url,
        details={"contentType": content_type},
    )]

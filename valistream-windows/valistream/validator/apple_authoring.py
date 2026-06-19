"""Apple HLS Authoring Specification validation rules."""

from __future__ import annotations

from valistream.parser.models import MasterPlaylist, MediaPlaylist, Rendition
from valistream.validator.finding import Finding, FindingCode, Severity

_VIDEO_CODEC_PREFIXES = ("avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe", "av01", "vp09")


def validate_apple_master(playlist: MasterPlaylist) -> list[Finding]:
    findings: list[Finding] = []
    findings.extend(_check_variant_attributes(playlist))
    findings.extend(_check_duplicate_bandwidth(playlist))
    if not playlist.is_independent_segments:
        findings.append(Finding(
            code=FindingCode.APPLE_INDEPENDENT_SEGMENTS,
            severity=Severity.WARNING,
            message="Master playlist should declare EXT-X-INDEPENDENT-SEGMENTS.",
            playlist_url=playlist.url,
        ))
    return findings


def validate_apple_media(playlist: MediaPlaylist) -> list[Finding]:
    if playlist.target_duration is None or playlist.target_duration <= 6:
        return []
    return [Finding(
        code=FindingCode.APPLE_TARGET_DURATION,
        severity=Severity.INFO,
        message=f"EXT-X-TARGETDURATION is {playlist.target_duration}s; Apple recommends 6 seconds or less.",
        playlist_url=playlist.url,
        details={"targetDuration": playlist.target_duration},
    )]


def _check_variant_attributes(playlist: MasterPlaylist) -> list[Finding]:
    findings: list[Finding] = []
    for v in playlist.variants:
        if not v.codecs:
            findings.append(Finding(
                code=FindingCode.APPLE_CODECS,
                severity=Severity.WARNING,
                message="EXT-X-STREAM-INF should declare a CODECS attribute.",
                playlist_url=playlist.url,
            ))
        if v.average_bandwidth is None:
            findings.append(Finding(
                code=FindingCode.APPLE_AVERAGE_BANDWIDTH,
                severity=Severity.WARNING,
                message="EXT-X-STREAM-INF should declare AVERAGE-BANDWIDTH.",
                playlist_url=playlist.url,
            ))
        if _expects_resolution(v) and not v.resolution:
            findings.append(Finding(
                code=FindingCode.APPLE_RESOLUTION,
                severity=Severity.WARNING,
                message="Video variant should declare a RESOLUTION attribute.",
                playlist_url=playlist.url,
            ))
    return findings


def _check_duplicate_bandwidth(playlist: MasterPlaylist) -> list[Finding]:
    seen: set[int] = set()
    findings: list[Finding] = []
    for v in playlist.variants:
        bw = v.bandwidth
        if bw in seen:
            findings.append(Finding(
                code=FindingCode.APPLE_VARIANT_LADDER,
                severity=Severity.WARNING,
                message=f"Multiple variants declare the same BANDWIDTH ({bw}); the ladder should use distinct bitrates.",
                playlist_url=playlist.url,
                details={"bandwidth": bw},
            ))
        seen.add(bw)
    return findings


def _expects_resolution(variant: Rendition) -> bool:
    if not variant.codecs:
        return True
    return any(
        codec.strip().startswith(prefix)
        for codec in variant.codecs.split(",")
        for prefix in _VIDEO_CODEC_PREFIXES
    )

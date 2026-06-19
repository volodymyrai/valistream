"""RFC 8216 validation rules for master and media playlists."""

from __future__ import annotations

from valistream.parser.models import MasterPlaylist, MediaPlaylist
from valistream.validator.finding import Finding, FindingCode, Severity

_VIDEO_CODEC_PREFIXES = ("avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe", "av01", "vp09")


def validate_rfc8216_media(playlist: MediaPlaylist) -> list[Finding]:
    findings: list[Finding] = []
    findings.extend(_check_target_duration(playlist))
    findings.extend(_check_segment_durations(playlist))
    return findings


def validate_rfc8216_master(playlist: MasterPlaylist) -> list[Finding]:
    findings: list[Finding] = []
    findings.extend(_check_variant_bandwidth(playlist))
    findings.extend(_check_media_required_attributes(playlist))
    findings.extend(_check_group_references(playlist))
    return findings


# --- Media playlist rules ---


def _check_target_duration(playlist: MediaPlaylist) -> list[Finding]:
    if playlist.target_duration is not None:
        return []
    return [Finding(
        code=FindingCode.RFC8216_4_3_3_1,
        severity=Severity.ERROR,
        message="Media playlist is missing the required EXT-X-TARGETDURATION tag.",
        playlist_url=playlist.url,
    )]


def _check_segment_durations(playlist: MediaPlaylist) -> list[Finding]:
    if playlist.target_duration is None:
        return []
    target = playlist.target_duration
    findings: list[Finding] = []
    for seg in playlist.segments:
        if round(seg.duration) > target:
            findings.append(Finding(
                code=FindingCode.RFC8216_4_3_3_1_DURATION,
                severity=Severity.ERROR,
                message=f"Segment duration {seg.duration}s exceeds EXT-X-TARGETDURATION of {target}s.",
                playlist_url=playlist.url,
                details={"duration": seg.duration, "targetDuration": target},
            ))
    return findings


# --- Master playlist rules ---


def _check_variant_bandwidth(playlist: MasterPlaylist) -> list[Finding]:
    findings: list[Finding] = []
    for v in playlist.variants:
        if v.bandwidth == 0:
            findings.append(Finding(
                code=FindingCode.RFC8216_4_3_4_2_BANDWIDTH,
                severity=Severity.ERROR,
                message="EXT-X-STREAM-INF is missing the required BANDWIDTH attribute.",
                playlist_url=playlist.url,
            ))
    return findings


def _check_media_required_attributes(playlist: MasterPlaylist) -> list[Finding]:
    findings: list[Finding] = []
    for rendition in playlist.media:
        missing: list[str] = []
        if not rendition.type:
            missing.append("TYPE")
        if not rendition.group_id:
            missing.append("GROUP-ID")
        if not rendition.name:
            missing.append("NAME")
        if missing:
            findings.append(Finding(
                code=FindingCode.RFC8216_4_3_4_1,
                severity=Severity.ERROR,
                message=f"EXT-X-MEDIA is missing required attribute(s): {', '.join(missing)}.",
                playlist_url=playlist.url,
                details={"missing": ",".join(missing)},
            ))
    return findings


def _check_group_references(playlist: MasterPlaylist) -> list[Finding]:
    groups: dict[str, set[str]] = {}
    for rendition in playlist.media:
        rtype = rendition.type or ""
        if rtype not in groups:
            groups[rtype] = set()
        if rendition.group_id:
            groups[rtype].add(rendition.group_id)

    findings: list[Finding] = []
    for variant in playlist.variants:
        refs = [
            ("AUDIO", "AUDIO", variant.audio),
            ("VIDEO", "VIDEO", variant.video),
            ("SUBTITLES", "SUBTITLES", variant.subtitles),
        ]
        for attr, rtype, value in refs:
            if not value or value == "NONE":
                continue
            if value not in groups.get(rtype, set()):
                findings.append(Finding(
                    code=FindingCode.RFC8216_4_3_4_2_1,
                    severity=Severity.ERROR,
                    message=f'Variant references {attr} group "{value}" with no matching EXT-X-MEDIA rendition.',
                    playlist_url=playlist.url,
                    details={"group": value},
                ))
    return findings

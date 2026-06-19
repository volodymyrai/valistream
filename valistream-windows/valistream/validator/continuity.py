"""Live stream continuity validation between consecutive playlist refreshes."""

from __future__ import annotations

from valistream.parser.models import MediaPlaylist
from valistream.validator.finding import Finding, FindingCode, Severity


def check_continuity(previous: MediaPlaylist, current: MediaPlaylist) -> list[Finding]:
    findings: list[Finding] = []

    if current.media_sequence < previous.media_sequence:
        findings.append(Finding(
            code=FindingCode.CONTINUITY_MEDIA_SEQUENCE,
            severity=Severity.ERROR,
            message=(
                f"EXT-X-MEDIA-SEQUENCE regressed from {previous.media_sequence} "
                f"to {current.media_sequence}; a live media sequence must never decrease."
            ),
            playlist_url=current.url,
            details={
                "previousMediaSequence": previous.media_sequence,
                "currentMediaSequence": current.media_sequence,
            },
        ))
        return findings

    advanced = current.media_sequence - previous.media_sequence
    if advanced > len(previous.segments):
        findings.append(Finding(
            code=FindingCode.CONTINUITY_HEAD_REMOVAL,
            severity=Severity.ERROR,
            message=(
                f"The media window advanced by {advanced} segments but the previous "
                f"playlist held only {len(previous.segments)}; segments were removed "
                f"from the head before a player could consume them."
            ),
            playlist_url=current.url,
            details={
                "advancedBy": advanced,
                "previousSegmentCount": len(previous.segments),
            },
        ))

    # Segment stability check on overlapping sequence numbers.
    overlap_start = current.media_sequence
    prev_end = previous.media_sequence + len(previous.segments) - 1
    curr_end = current.media_sequence + len(current.segments) - 1
    overlap_end = min(prev_end, curr_end)

    if overlap_start <= overlap_end:
        for seq in range(overlap_start, overlap_end + 1):
            prev_idx = seq - previous.media_sequence
            curr_idx = seq - current.media_sequence
            if prev_idx < 0 or prev_idx >= len(previous.segments):
                continue
            prev_seg = previous.segments[prev_idx]
            curr_seg = current.segments[curr_idx]
            if prev_seg.uri != curr_seg.uri or prev_seg.duration != curr_seg.duration:
                findings.append(Finding(
                    code=FindingCode.CONTINUITY_SEGMENT_STABILITY,
                    severity=Severity.ERROR,
                    message=(
                        f"Segment at media sequence {seq} changed between refreshes; "
                        f"already-published segments must not be mutated retroactively."
                    ),
                    playlist_url=current.url,
                    details={
                        "mediaSequence": seq,
                        "previousURI": prev_seg.uri,
                        "currentURI": curr_seg.uri,
                    },
                ))

    # New discontinuity at tail (informational).
    prev_last_seq = previous.media_sequence + len(previous.segments) - 1
    for idx, seg in enumerate(current.segments):
        if seg.discontinuity:
            seq = current.media_sequence + idx
            if seq > prev_last_seq:
                findings.append(Finding(
                    code=FindingCode.CONTINUITY_DISCONTINUITY_INSERTED,
                    severity=Severity.INFO,
                    message=f"A discontinuity was inserted at media sequence {seq}.",
                    playlist_url=current.url,
                    details={"mediaSequence": seq},
                ))

    if current.discontinuity_sequence < previous.discontinuity_sequence:
        findings.append(Finding(
            code=FindingCode.CONTINUITY_DISCONTINUITY_SEQUENCE,
            severity=Severity.ERROR,
            message=(
                f"EXT-X-DISCONTINUITY-SEQUENCE regressed from "
                f"{previous.discontinuity_sequence} to {current.discontinuity_sequence}."
            ),
            playlist_url=current.url,
            details={
                "previousDiscontinuitySequence": previous.discontinuity_sequence,
                "currentDiscontinuitySequence": current.discontinuity_sequence,
            },
        ))

    return findings

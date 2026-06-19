"""SessionState — session ID, rendition selection, findings accumulator."""

from __future__ import annotations

import asyncio
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

from valistream.parser.models import MasterPlaylist, Rendition, StreamType
from valistream.validator.finding import Finding

_SLUG_RE = re.compile(r"[^a-z0-9]+")
_MAX_SLUG_LEN = 40


def make_session_id(url: str, now: datetime | None = None) -> str:
    now = now or datetime.now(timezone.utc)
    timestamp = now.strftime("%Y%m%dT%H%M%S")
    parsed = urlparse(url)
    host = parsed.hostname or "unknown"
    path = parsed.path.rstrip("/").rsplit("/", 1)[-1] if parsed.path else ""
    raw = f"{host}-{path}" if path else host
    slug = _SLUG_RE.sub("-", raw.lower()).strip("-") or "stream"
    slug = slug[:_MAX_SLUG_LEN].rstrip("-")
    return f"{timestamp}_{slug}"


def select_renditions(
    master: MasterPlaylist,
    preselect: str | None = None,
) -> list[Rendition]:
    if not master.variants:
        return []
    if preselect is None:
        return list(master.variants)
    pattern = re.compile(preselect, re.IGNORECASE)
    matched = [v for v in master.variants if _rendition_matches(v, pattern)]
    return matched if matched else list(master.variants)


def _rendition_matches(rendition: Rendition, pattern: re.Pattern[str]) -> bool:
    candidates = [
        rendition.uri,
        rendition.alias,
        rendition.resolution or "",
        rendition.codecs or "",
        str(rendition.bandwidth),
    ]
    return any(pattern.search(c) for c in candidates)


def classify_stream(body: str) -> StreamType:
    if "#EXT-X-ENDLIST" in body:
        return StreamType.VOD
    return StreamType.LIVE


@dataclass
class SessionState:
    """Mutable state shared across an active validation session."""

    session_id: str = ""
    url: str = ""
    output_dir: Path | None = None
    stream_type: StreamType | None = None
    selected_renditions: list[Rendition] = field(default_factory=list)
    findings: list[Finding] = field(default_factory=list)
    started_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    ended_at: datetime | None = None
    cancelled: bool = False
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    def add_finding(self, finding: Finding) -> None:
        self.findings.append(finding)

    def add_findings(self, findings: list[Finding]) -> None:
        self.findings.extend(findings)

    def finish(self) -> None:
        self.ended_at = datetime.now(timezone.utc)

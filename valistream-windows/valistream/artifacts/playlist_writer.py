"""Write NNNNNN.m3u8 snapshots and NNNNNN.meta.json sidecars."""

from __future__ import annotations

import json
from pathlib import Path


def write_playlist_snapshot(
    output_dir: Path,
    alias: str,
    sequence: int,
    body: str,
) -> Path:
    rendition_dir = output_dir / "playlists" / alias
    rendition_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{alias}_{sequence:06d}.m3u8"
    path = rendition_dir / filename
    path.write_text(body, encoding="utf-8", newline="\n")
    return path


def write_meta_json(
    output_dir: Path,
    alias: str,
    sequence: int,
    meta: dict[str, object],
) -> Path:
    rendition_dir = output_dir / "playlists" / alias
    rendition_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{alias}_{sequence:06d}.meta.json"
    path = rendition_dir / filename
    text = json.dumps(meta, indent=2, sort_keys=True, ensure_ascii=False)
    path.write_text(text + "\n", encoding="utf-8", newline="\n")
    return path

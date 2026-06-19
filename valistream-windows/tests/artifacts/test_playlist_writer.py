"""Tests for playlist snapshot and meta.json writers."""

from __future__ import annotations

import json
from pathlib import Path

from valistream.artifacts.playlist_writer import write_meta_json, write_playlist_snapshot


class TestWritePlaylistSnapshot:
    def test_creates_file_with_correct_name(self, tmp_path: Path) -> None:
        body = "#EXTM3U\n#EXTINF:6.0,\nseg0.ts\n"
        path = write_playlist_snapshot(tmp_path, "v720p", 0, body)
        assert path.name == "v720p_000000.m3u8"
        assert path.exists()

    def test_content_matches_body(self, tmp_path: Path) -> None:
        body = "#EXTM3U\n#EXTINF:6.0,\nseg0.ts\n"
        path = write_playlist_snapshot(tmp_path, "v720p", 0, body)
        assert path.read_text(encoding="utf-8") == body

    def test_sequence_zero_padding(self, tmp_path: Path) -> None:
        path = write_playlist_snapshot(tmp_path, "v1080p", 42, "body")
        assert path.name == "v1080p_000042.m3u8"

    def test_creates_subdirectory(self, tmp_path: Path) -> None:
        write_playlist_snapshot(tmp_path, "audio-en", 0, "body")
        assert (tmp_path / "playlists" / "audio-en").is_dir()

    def test_multiple_writes_same_rendition(self, tmp_path: Path) -> None:
        write_playlist_snapshot(tmp_path, "v720p", 0, "first")
        write_playlist_snapshot(tmp_path, "v720p", 1, "second")
        assert (tmp_path / "playlists" / "v720p" / "v720p_000000.m3u8").exists()
        assert (tmp_path / "playlists" / "v720p" / "v720p_000001.m3u8").exists()

    def test_utf8_encoding(self, tmp_path: Path) -> None:
        body = "#EXTM3U\n# Comment with ñ and ü\n"
        path = write_playlist_snapshot(tmp_path, "intl", 0, body)
        assert path.read_text(encoding="utf-8") == body


class TestWriteMetaJson:
    def test_creates_file_with_correct_name(self, tmp_path: Path) -> None:
        meta = {"url": "https://cdn.example.com/720p.m3u8", "status": 200}
        path = write_meta_json(tmp_path, "v720p", 0, meta)
        assert path.name == "v720p_000000.meta.json"
        assert path.exists()

    def test_content_is_valid_json(self, tmp_path: Path) -> None:
        meta = {"url": "https://cdn.example.com/720p.m3u8", "status": 200}
        path = write_meta_json(tmp_path, "v720p", 0, meta)
        parsed = json.loads(path.read_text(encoding="utf-8"))
        assert parsed["url"] == "https://cdn.example.com/720p.m3u8"
        assert parsed["status"] == 200

    def test_sorted_keys(self, tmp_path: Path) -> None:
        meta = {"z_field": 1, "a_field": 2}
        path = write_meta_json(tmp_path, "v720p", 0, meta)
        text = path.read_text(encoding="utf-8")
        assert text.index('"a_field"') < text.index('"z_field"')

    def test_pretty_printed(self, tmp_path: Path) -> None:
        meta = {"key": "value"}
        path = write_meta_json(tmp_path, "v720p", 0, meta)
        text = path.read_text(encoding="utf-8")
        assert "\n" in text
        assert "  " in text

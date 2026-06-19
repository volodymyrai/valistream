"""End-to-end CLI tests using Click's CliRunner and mocked HTTP."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest
from click.testing import CliRunner

from valistream.cli.app import main
from valistream.fetch.result import FetchResult


MASTER_PLAYLIST = """\
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2560000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
1080p.m3u8
"""

MEDIA_PLAYLIST_VOD = """\
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:10.0,
segment0.ts
#EXTINF:10.0,
segment1.ts
#EXT-X-ENDLIST
"""

MEDIA_PLAYLIST_LIVE = """\
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:100
#EXTINF:6.0,
segment100.ts
#EXTINF:6.0,
segment101.ts
"""

MASTER_URL = "https://example.com/stream/master.m3u8"
MEDIA_720_URL = "https://example.com/stream/720p.m3u8"
MEDIA_1080_URL = "https://example.com/stream/1080p.m3u8"


def _make_fetch_result(url: str, body: str, status: int = 200) -> FetchResult:
    return FetchResult(
        url=url,
        status_code=status,
        body=body,
        headers={"Content-Type": "application/vnd.apple.mpegurl"},
        response_time_ms=50.0,
    )


def _make_mock_client(responses: dict[str, FetchResult]) -> AsyncMock:
    client = AsyncMock()

    async def fetch(url: str) -> FetchResult:
        return responses.get(url, FetchResult(url=url, status_code=404, body=""))

    client.fetch = fetch
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=None)
    return client


class TestVersionFlag:
    def test_version(self) -> None:
        runner = CliRunner()
        result = runner.invoke(main, ["--version"])
        assert result.exit_code == 0
        assert "valistream" in result.output
        assert "0.6.0" in result.output


class TestHelpFlag:
    def test_help(self) -> None:
        runner = CliRunner()
        result = runner.invoke(main, ["-h"])
        assert result.exit_code == 0
        assert "RFC 8216" in result.output
        assert "--limit" in result.output
        assert "--preselect" in result.output
        assert "--select" in result.output
        assert "--non-interactive" in result.output
        assert "--output-dir" in result.output
        assert "--json" in result.output
        assert "--quiet" in result.output
        assert "--verbose" in result.output
        assert "--no-color" in result.output

    def test_long_help(self) -> None:
        runner = CliRunner()
        result = runner.invoke(main, ["--help"])
        assert result.exit_code == 0
        assert "URL" in result.output


class TestLimitFlag:
    def test_invalid_limit(self) -> None:
        runner = CliRunner()
        result = runner.invoke(main, [MASTER_URL, "--limit", "abc"])
        assert result.exit_code == 2

    def test_valid_limit_formats(self) -> None:
        from valistream.cli.time_limit import parse_time_limit

        assert parse_time_limit("90s") == 90.0
        assert parse_time_limit("15m") == 900.0
        assert parse_time_limit("24h") == 86400.0


class TestVODSession:
    def test_vod_basic(self, tmp_path: Path) -> None:
        responses = {
            MASTER_URL: _make_fetch_result(MASTER_URL, MASTER_PLAYLIST),
            MEDIA_720_URL: _make_fetch_result(MEDIA_720_URL, MEDIA_PLAYLIST_VOD),
            MEDIA_1080_URL: _make_fetch_result(MEDIA_1080_URL, MEDIA_PLAYLIST_VOD),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            result = runner.invoke(
                main,
                [MASTER_URL, "--output-dir", str(tmp_path), "--non-interactive"],
            )

        assert result.exit_code in (0, 1)
        session_dirs = list(tmp_path.iterdir())
        assert len(session_dirs) == 1

        session_dir = session_dirs[0]
        assert (session_dir / "report.json").exists()
        assert (session_dir / "report.md").exists()
        assert (session_dir / "findings.jsonl").exists()

    def test_vod_json_output(self, tmp_path: Path) -> None:
        responses = {
            MASTER_URL: _make_fetch_result(MASTER_URL, MASTER_PLAYLIST),
            MEDIA_720_URL: _make_fetch_result(MEDIA_720_URL, MEDIA_PLAYLIST_VOD),
            MEDIA_1080_URL: _make_fetch_result(MEDIA_1080_URL, MEDIA_PLAYLIST_VOD),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            result = runner.invoke(
                main,
                [MASTER_URL, "--output-dir", str(tmp_path), "--json", "--non-interactive"],
            )

        assert result.exit_code in (0, 1)
        lines = [l for l in result.output.strip().split("\n") if l.strip()]
        for line in lines:
            parsed = json.loads(line)
            assert "code" in parsed or "type" in parsed

    def test_vod_quiet_mode(self, tmp_path: Path) -> None:
        responses = {
            MASTER_URL: _make_fetch_result(MASTER_URL, MASTER_PLAYLIST),
            MEDIA_720_URL: _make_fetch_result(MEDIA_720_URL, MEDIA_PLAYLIST_VOD),
            MEDIA_1080_URL: _make_fetch_result(MEDIA_1080_URL, MEDIA_PLAYLIST_VOD),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            result = runner.invoke(
                main,
                [MASTER_URL, "--output-dir", str(tmp_path), "--quiet", "--non-interactive"],
            )

        assert result.exit_code in (0, 1)

    def test_vod_verbose_mode(self, tmp_path: Path) -> None:
        responses = {
            MASTER_URL: _make_fetch_result(MASTER_URL, MASTER_PLAYLIST),
            MEDIA_720_URL: _make_fetch_result(MEDIA_720_URL, MEDIA_PLAYLIST_VOD),
            MEDIA_1080_URL: _make_fetch_result(MEDIA_1080_URL, MEDIA_PLAYLIST_VOD),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            result = runner.invoke(
                main,
                [MASTER_URL, "--output-dir", str(tmp_path), "--verbose", "--non-interactive"],
            )

        assert result.exit_code in (0, 1)

    def test_vod_no_color(self, tmp_path: Path) -> None:
        responses = {
            MASTER_URL: _make_fetch_result(MASTER_URL, MASTER_PLAYLIST),
            MEDIA_720_URL: _make_fetch_result(MEDIA_720_URL, MEDIA_PLAYLIST_VOD),
            MEDIA_1080_URL: _make_fetch_result(MEDIA_1080_URL, MEDIA_PLAYLIST_VOD),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            result = runner.invoke(
                main,
                [MASTER_URL, "--output-dir", str(tmp_path), "--no-color", "--non-interactive"],
            )

        assert result.exit_code in (0, 1)


class TestPreselectFlag:
    def test_preselect_filters(self, tmp_path: Path) -> None:
        responses = {
            MASTER_URL: _make_fetch_result(MASTER_URL, MASTER_PLAYLIST),
            MEDIA_720_URL: _make_fetch_result(MEDIA_720_URL, MEDIA_PLAYLIST_VOD),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            result = runner.invoke(
                main,
                [MASTER_URL, "--output-dir", str(tmp_path), "--preselect", "720p"],
            )

        assert result.exit_code in (0, 1)
        session_dirs = list(tmp_path.iterdir())
        assert len(session_dirs) == 1


class TestFetchFailure:
    def test_http_error(self) -> None:
        responses = {
            MASTER_URL: FetchResult(url=MASTER_URL, status_code=404, body=""),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            result = runner.invoke(main, [MASTER_URL])

        assert result.exit_code == 1

    def test_unparseable_playlist(self, tmp_path: Path) -> None:
        responses = {
            MASTER_URL: _make_fetch_result(MASTER_URL, "not a playlist"),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            result = runner.invoke(
                main, [MASTER_URL, "--output-dir", str(tmp_path)]
            )

        assert result.exit_code == 1


class TestReportArtifacts:
    def test_report_json_schema(self, tmp_path: Path) -> None:
        responses = {
            MASTER_URL: _make_fetch_result(MASTER_URL, MASTER_PLAYLIST),
            MEDIA_720_URL: _make_fetch_result(MEDIA_720_URL, MEDIA_PLAYLIST_VOD),
            MEDIA_1080_URL: _make_fetch_result(MEDIA_1080_URL, MEDIA_PLAYLIST_VOD),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            runner.invoke(
                main,
                [MASTER_URL, "--output-dir", str(tmp_path), "--non-interactive"],
            )

        session_dir = list(tmp_path.iterdir())[0]
        report = json.loads((session_dir / "report.json").read_text(encoding="utf-8"))

        assert report["schema_version"] == 1
        assert "session" in report
        assert "findings" in report
        assert "renditions" in report
        assert "summary" in report
        assert report["session"]["url"] == MASTER_URL

    def test_findings_jsonl_format(self, tmp_path: Path) -> None:
        responses = {
            MASTER_URL: _make_fetch_result(MASTER_URL, MASTER_PLAYLIST),
            MEDIA_720_URL: _make_fetch_result(MEDIA_720_URL, MEDIA_PLAYLIST_VOD),
            MEDIA_1080_URL: _make_fetch_result(MEDIA_1080_URL, MEDIA_PLAYLIST_VOD),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            runner.invoke(
                main,
                [MASTER_URL, "--output-dir", str(tmp_path), "--non-interactive"],
            )

        session_dir = list(tmp_path.iterdir())[0]
        findings_path = session_dir / "findings.jsonl"
        text = findings_path.read_text(encoding="utf-8")
        for line in text.strip().split("\n"):
            if line.strip():
                parsed = json.loads(line)
                assert "code" in parsed
                assert "severity" in parsed
                assert "message" in parsed
                assert parsed["severity"] in ("error", "warning", "info")

    def test_report_md_sections(self, tmp_path: Path) -> None:
        responses = {
            MASTER_URL: _make_fetch_result(MASTER_URL, MASTER_PLAYLIST),
            MEDIA_720_URL: _make_fetch_result(MEDIA_720_URL, MEDIA_PLAYLIST_VOD),
            MEDIA_1080_URL: _make_fetch_result(MEDIA_1080_URL, MEDIA_PLAYLIST_VOD),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            runner.invoke(
                main,
                [MASTER_URL, "--output-dir", str(tmp_path), "--non-interactive"],
            )

        session_dir = list(tmp_path.iterdir())[0]
        md = (session_dir / "report.md").read_text(encoding="utf-8")

        assert "# Valistream Report" in md
        assert "## Stream Info" in md
        assert "## Findings Summary" in md
        assert "## Renditions" in md


class TestMediaPlaylistDirect:
    """Test handling when URL points to a media playlist directly (not master)."""

    def test_media_playlist_url(self, tmp_path: Path) -> None:
        responses = {
            MEDIA_720_URL: _make_fetch_result(MEDIA_720_URL, MEDIA_PLAYLIST_VOD),
        }
        mock_client = _make_mock_client(responses)

        with patch("valistream.fetch.client.HLSClient", return_value=mock_client):
            runner = CliRunner()
            result = runner.invoke(
                main,
                [MEDIA_720_URL, "--output-dir", str(tmp_path)],
            )

        assert result.exit_code in (0, 1)
        session_dirs = list(tmp_path.iterdir())
        assert len(session_dirs) == 1

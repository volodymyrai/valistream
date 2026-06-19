"""Tests for interactive rendition selector."""

from __future__ import annotations

from unittest.mock import patch

from valistream.parser.models import Rendition
from valistream.terminal.selector import _rendition_label, select_renditions_interactive


def _rendition(
    uri: str = "720p.m3u8",
    bandwidth: int = 1280000,
    resolution: str | None = "1280x720",
    codecs: str | None = "avc1.4d401f",
) -> Rendition:
    return Rendition(uri=uri, bandwidth=bandwidth, resolution=resolution, codecs=codecs)


class TestRenditionLabel:
    def test_includes_alias(self) -> None:
        r = _rendition()
        label = _rendition_label(r)
        assert r.alias in label

    def test_includes_resolution(self) -> None:
        label = _rendition_label(_rendition(resolution="1280x720"))
        assert "1280x720" in label

    def test_includes_bandwidth(self) -> None:
        label = _rendition_label(_rendition(bandwidth=1280000))
        assert "1280k" in label

    def test_includes_codecs(self) -> None:
        label = _rendition_label(_rendition(codecs="avc1.4d401f"))
        assert "avc1.4d401f" in label


class TestSelectRenditionsInteractive:
    def test_empty_list_returns_empty(self) -> None:
        assert select_renditions_interactive([]) == []

    def test_non_tty_returns_all(self) -> None:
        renditions = [_rendition(), _rendition(uri="1080p.m3u8")]
        with patch("sys.stdin") as mock_stdin:
            mock_stdin.isatty.return_value = False
            result = select_renditions_interactive(renditions)
        assert len(result) == 2

    def test_cancelled_returns_all(self) -> None:
        renditions = [_rendition()]
        with patch("sys.stdin") as mock_stdin:
            mock_stdin.isatty.return_value = True
            with patch("valistream.terminal.selector.questionary") as mock_q:
                mock_q.Choice = lambda **kw: kw
                mock_q.checkbox.return_value.ask.return_value = None
                result = select_renditions_interactive(renditions)
        assert len(result) == 1

    def test_selection_returned(self) -> None:
        r1 = _rendition(uri="720p.m3u8")
        r2 = _rendition(uri="1080p.m3u8")
        with patch("sys.stdin") as mock_stdin:
            mock_stdin.isatty.return_value = True
            with patch("valistream.terminal.selector.questionary") as mock_q:
                mock_q.Choice = lambda **kw: kw
                mock_q.checkbox.return_value.ask.return_value = [r1]
                result = select_renditions_interactive([r1, r2])
        assert result == [r1]

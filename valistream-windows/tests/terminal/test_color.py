"""Tests for NO_COLOR / --no-color handling."""

from __future__ import annotations

import os
from unittest.mock import patch

from valistream.terminal.color import init_color, should_use_color


class TestShouldUseColor:
    def test_flag_disables(self) -> None:
        assert should_use_color(no_color_flag=True) is False

    def test_env_var_disables(self) -> None:
        with patch.dict(os.environ, {"NO_COLOR": "1"}):
            assert should_use_color(no_color_flag=False) is False

    def test_empty_env_var_disables(self) -> None:
        with patch.dict(os.environ, {"NO_COLOR": ""}):
            assert should_use_color(no_color_flag=False) is False

    def test_no_tty_disables(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            with patch("sys.stdout") as mock_stdout:
                mock_stdout.isatty.return_value = False
                assert should_use_color(no_color_flag=False) is False

    def test_tty_enables(self) -> None:
        env = {k: v for k, v in os.environ.items() if k != "NO_COLOR"}
        with patch.dict(os.environ, env, clear=True):
            with patch("sys.stdout") as mock_stdout:
                mock_stdout.isatty.return_value = True
                assert should_use_color(no_color_flag=False) is True


class TestInitColor:
    def test_disabled_does_nothing(self) -> None:
        init_color(False)

    def test_enabled_runs_without_error(self) -> None:
        init_color(True)

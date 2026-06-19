"""Tests for time limit parser."""

from __future__ import annotations

import pytest

from valistream.cli.time_limit import parse_time_limit


class TestParseTimeLimit:
    def test_bare_number(self) -> None:
        assert parse_time_limit("90") == 90.0

    def test_seconds_suffix(self) -> None:
        assert parse_time_limit("90s") == 90.0

    def test_seconds_upper(self) -> None:
        assert parse_time_limit("90S") == 90.0

    def test_minutes(self) -> None:
        assert parse_time_limit("15m") == 900.0

    def test_hours(self) -> None:
        assert parse_time_limit("24h") == 86400.0

    def test_float_value(self) -> None:
        assert parse_time_limit("1.5h") == 5400.0

    def test_whitespace_stripped(self) -> None:
        assert parse_time_limit("  90s  ") == 90.0

    def test_invalid_format(self) -> None:
        with pytest.raises(ValueError, match="Invalid time limit"):
            parse_time_limit("abc")

    def test_empty_string(self) -> None:
        with pytest.raises(ValueError):
            parse_time_limit("")

    def test_negative_value(self) -> None:
        with pytest.raises(ValueError):
            parse_time_limit("-10s")

    def test_zero(self) -> None:
        with pytest.raises(ValueError, match="positive"):
            parse_time_limit("0s")

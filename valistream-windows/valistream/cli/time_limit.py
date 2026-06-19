"""Parse time-limit strings like '90s', '15m', '24h' into seconds."""

from __future__ import annotations

import re

_TIME_RE = re.compile(r"^(\d+(?:\.\d+)?)\s*([smh]?)$", re.IGNORECASE)

_MULTIPLIERS = {
    "": 1.0,
    "s": 1.0,
    "m": 60.0,
    "h": 3600.0,
}


def parse_time_limit(value: str) -> float:
    """Parse a time-limit string and return the duration in seconds.

    Accepts formats: '90', '90s', '15m', '24h', '1.5h'.
    """
    match = _TIME_RE.match(value.strip())
    if not match:
        raise ValueError(
            f"Invalid time limit {value!r}. "
            "Use a number with optional suffix: 90s, 15m, 24h."
        )
    amount = float(match.group(1))
    unit = match.group(2).lower()
    result = amount * _MULTIPLIERS[unit]
    if result <= 0:
        raise ValueError("Time limit must be positive.")
    return result

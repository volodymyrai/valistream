"""KITT-style pulsating scanner bar for terminal output."""

from __future__ import annotations

from rich.text import Text

# Gradient: distance from beam center → (character, style)
_GRADIENT = [
    ("█", "bold bright_red"),
    ("▓", "bright_red"),
    ("▒", "red"),
    ("░", "dark_red"),
]
_BG_CHAR = "░"
_BG_STYLE = "grey23"

# ASCII fallback when color is disabled
_ASCII_BEAM = ["O", "o", ".", " "]
_ASCII_BG = " "


class ScannerBar:
    """Bouncing scanner bar in the style of KITT's anamorphic equalizer."""

    def __init__(self, width: int = 60, *, color: bool = True) -> None:
        self._width = width
        self._color = color
        self._pos: int = 0
        self._direction: int = 1

    def advance(self) -> None:
        self._pos += self._direction
        if self._pos >= self._width - 1:
            self._direction = -1
        elif self._pos <= 0:
            self._direction = 1

    def render(self) -> Text:
        bar = Text(no_wrap=True, overflow="crop")
        gradient = _GRADIENT if self._color else [
            (c, "") for c in _ASCII_BEAM
        ]
        bg_char = _BG_CHAR if self._color else _ASCII_BG
        bg_style = _BG_STYLE if self._color else ""

        for i in range(self._width):
            dist = abs(i - self._pos)
            if dist < len(gradient):
                ch, style = gradient[dist]
                bar.append(ch, style=style)
            else:
                bar.append(bg_char, style=bg_style)

        return bar

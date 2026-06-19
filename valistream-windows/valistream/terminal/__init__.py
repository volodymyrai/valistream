"""Terminal output — live display, findings printer, summary, selector, color."""

from valistream.terminal.color import init_color, should_use_color
from valistream.terminal.display import LiveDisplay, RenditionStatus, create_live_display
from valistream.terminal.findings_printer import print_finding, print_finding_json
from valistream.terminal.summary import print_summary, print_summary_json

__all__ = [
    "LiveDisplay",
    "RenditionStatus",
    "create_live_display",
    "init_color",
    "print_finding",
    "print_finding_json",
    "print_summary",
    "print_summary_json",
    "should_use_color",
]

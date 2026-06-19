"""Tag attribute parsing utilities."""

from __future__ import annotations

import re

_ATTR_RE = re.compile(
    r'(?P<key>[A-Z0-9-]+)\s*=\s*(?:"(?P<qval>[^"]*)"|(?P<val>[^,\s]*))'
)


def parse_attribute_list(raw: str) -> dict[str, str]:
    """Parse an HLS tag attribute list into key-value pairs.

    Handles both quoted and unquoted values per RFC 8216 §4.2.
    """
    attrs: dict[str, str] = {}
    for m in _ATTR_RE.finditer(raw):
        key = m.group("key")
        value = m.group("qval") if m.group("qval") is not None else m.group("val")
        attrs[key] = value
    return attrs

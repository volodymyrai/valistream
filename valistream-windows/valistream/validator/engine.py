"""Validator engine — runs all rule sets against parsed playlists."""

from __future__ import annotations

from valistream.parser.models import MasterPlaylist, MediaPlaylist
from valistream.validator.apple_authoring import validate_apple_master, validate_apple_media
from valistream.validator.finding import Finding
from valistream.validator.rfc8216 import validate_rfc8216_master, validate_rfc8216_media


def validate_master(playlist: MasterPlaylist) -> list[Finding]:
    findings: list[Finding] = []
    findings.extend(validate_rfc8216_master(playlist))
    findings.extend(validate_apple_master(playlist))
    return findings


def validate_media(playlist: MediaPlaylist) -> list[Finding]:
    findings: list[Finding] = []
    findings.extend(validate_rfc8216_media(playlist))
    findings.extend(validate_apple_media(playlist))
    return findings

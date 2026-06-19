"""Tests for VOD single-pass validation."""

from __future__ import annotations

from dataclasses import dataclass, field

import pytest

from valistream.monitor.session import SessionState, make_session_id, select_renditions
from valistream.monitor.vod import validate_vod
from valistream.parser.models import MasterPlaylist, Rendition
from valistream.validator.finding import FindingCode, Severity

MASTER_URL = "https://cdn.example.com/master.m3u8"
MEDIA_URL = "https://cdn.example.com/720p.m3u8"


@dataclass
class FakeFetchResult:
    url: str
    status_code: int
    body: str
    headers: dict[str, str] = field(default_factory=dict)
    response_time_ms: float = 10.0
    redirected_url: str | None = None

    @property
    def ok(self) -> bool:
        return 200 <= self.status_code < 400


class FakeClient:
    def __init__(self, responses: dict[str, FakeFetchResult]) -> None:
        self._responses = responses

    async def fetch(self, url: str) -> FakeFetchResult:
        return self._responses.get(url, FakeFetchResult(url=url, status_code=404, body=""))


GOOD_MEDIA_BODY = """\
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:5.5,
seg0.ts
#EXTINF:6.0,
seg1.ts
#EXTINF:5.8,
seg2.ts
#EXT-X-ENDLIST
"""

BAD_MEDIA_BODY = """\
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXTINF:12.0,
long-segment.ts
#EXT-X-ENDLIST
"""


def _make_session(master: MasterPlaylist, preselect: str | None = None) -> SessionState:
    session = SessionState(
        session_id=make_session_id(master.url),
        url=master.url,
    )
    session.selected_renditions = select_renditions(master, preselect=preselect)
    return session


class TestVodValidation:
    @pytest.mark.asyncio
    async def test_end_to_end_clean(self) -> None:
        master = MasterPlaylist(
            url=MASTER_URL,
            is_independent_segments=True,
            variants=[
                Rendition(
                    uri=MEDIA_URL,
                    bandwidth=1280000,
                    resolution="1280x720",
                    codecs="avc1.4d401f,mp4a.40.2",
                    average_bandwidth=1000000,
                ),
            ],
        )
        client = FakeClient({
            MEDIA_URL: FakeFetchResult(
                url=MEDIA_URL,
                status_code=200,
                body=GOOD_MEDIA_BODY,
                headers={"Content-Type": "application/vnd.apple.mpegurl"},
            ),
        })
        session = _make_session(master)
        await validate_vod(session, master, client)

        errors = [f for f in session.findings if f.severity == Severity.ERROR]
        assert len(errors) == 0
        assert session.ended_at is not None

    @pytest.mark.asyncio
    async def test_detects_master_and_media_errors(self) -> None:
        master = MasterPlaylist(
            url=MASTER_URL,
            variants=[
                Rendition(uri=MEDIA_URL, bandwidth=0),
            ],
        )
        client = FakeClient({
            MEDIA_URL: FakeFetchResult(
                url=MEDIA_URL,
                status_code=200,
                body=BAD_MEDIA_BODY,
                headers={"Content-Type": "text/plain"},
            ),
        })
        session = _make_session(master)
        await validate_vod(session, master, client)

        codes = {f.code for f in session.findings}
        assert FindingCode.RFC8216_4_3_4_2_BANDWIDTH in codes
        assert FindingCode.APPLE_CODECS in codes
        assert FindingCode.RFC8216_4_3_3_1_DURATION in codes
        assert FindingCode.DELIVERY_CONTENT_TYPE in codes

    @pytest.mark.asyncio
    async def test_skips_failed_fetch(self) -> None:
        master = MasterPlaylist(
            url=MASTER_URL,
            is_independent_segments=True,
            variants=[
                Rendition(
                    uri=MEDIA_URL,
                    bandwidth=1280000,
                    codecs="avc1.4d401f",
                    resolution="1280x720",
                    average_bandwidth=1000000,
                ),
            ],
        )
        client = FakeClient({})  # returns 404 for everything
        session = _make_session(master)
        await validate_vod(session, master, client)

        media_findings = [
            f for f in session.findings
            if f.code in (FindingCode.RFC8216_4_3_3_1, FindingCode.RFC8216_4_3_3_1_DURATION)
        ]
        assert len(media_findings) == 0
        assert session.ended_at is not None

    @pytest.mark.asyncio
    async def test_multiple_renditions(self) -> None:
        media_url_2 = "https://cdn.example.com/1080p.m3u8"
        master = MasterPlaylist(
            url=MASTER_URL,
            is_independent_segments=True,
            variants=[
                Rendition(
                    uri=MEDIA_URL, bandwidth=1280000,
                    resolution="1280x720", codecs="avc1.4d401f",
                    average_bandwidth=1000000,
                ),
                Rendition(
                    uri=media_url_2, bandwidth=2560000,
                    resolution="1920x1080", codecs="avc1.640028",
                    average_bandwidth=2000000,
                ),
            ],
        )
        client = FakeClient({
            MEDIA_URL: FakeFetchResult(
                url=MEDIA_URL, status_code=200,
                body=GOOD_MEDIA_BODY,
                headers={"Content-Type": "application/vnd.apple.mpegurl"},
            ),
            media_url_2: FakeFetchResult(
                url=media_url_2, status_code=200,
                body=GOOD_MEDIA_BODY,
                headers={"Content-Type": "application/vnd.apple.mpegurl"},
            ),
        })
        session = _make_session(master)
        await validate_vod(session, master, client)

        assert session.ended_at is not None
        errors = [f for f in session.findings if f.severity == Severity.ERROR]
        assert len(errors) == 0

    @pytest.mark.asyncio
    async def test_preselect_filters_renditions(self) -> None:
        media_url_2 = "https://cdn.example.com/1080p.m3u8"
        master = MasterPlaylist(
            url=MASTER_URL,
            is_independent_segments=True,
            variants=[
                Rendition(
                    uri=MEDIA_URL, bandwidth=1280000,
                    resolution="1280x720", codecs="avc1.4d401f",
                    average_bandwidth=1000000,
                ),
                Rendition(
                    uri=media_url_2, bandwidth=2560000,
                    resolution="1920x1080", codecs="avc1.640028",
                    average_bandwidth=2000000,
                ),
            ],
        )
        fetch_log: list[str] = []

        class LoggingClient:
            async def fetch(self, url: str) -> FakeFetchResult:
                fetch_log.append(url)
                return FakeFetchResult(
                    url=url, status_code=200,
                    body=GOOD_MEDIA_BODY,
                    headers={"Content-Type": "application/vnd.apple.mpegurl"},
                )

        session = _make_session(master, preselect="720")
        assert len(session.selected_renditions) == 1
        await validate_vod(session, master, LoggingClient())

        assert MEDIA_URL in fetch_log
        assert media_url_2 not in fetch_log

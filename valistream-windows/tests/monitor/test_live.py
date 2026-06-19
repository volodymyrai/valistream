"""Tests for live monitoring loop with mocked client."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field

import pytest

from valistream.monitor.live import monitor_live
from valistream.monitor.session import SessionState, make_session_id, select_renditions
from valistream.parser.models import MasterPlaylist, Rendition
from valistream.validator.finding import FindingCode, Severity

MASTER_URL = "https://cdn.example.com/master.m3u8"
MEDIA_URL = "https://cdn.example.com/720p.m3u8"


def _live_playlist(seq: int, segments: list[str], target: int = 6, endlist: bool = False) -> str:
    lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:3",
        f"#EXT-X-TARGETDURATION:{target}",
        f"#EXT-X-MEDIA-SEQUENCE:{seq}",
    ]
    for s in segments:
        lines.append(f"#EXTINF:{target}.0,")
        lines.append(s)
    if endlist:
        lines.append("#EXT-X-ENDLIST")
    lines.append("")
    return "\n".join(lines)


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


class SequentialClient:
    """Returns a sequence of responses for a given URL, repeating the last one."""

    def __init__(self, url: str, responses: list[str]) -> None:
        self._url = url
        self._responses = responses
        self._call_count = 0

    async def fetch(self, url: str) -> FakeFetchResult:
        idx = min(self._call_count, len(self._responses) - 1)
        body = self._responses[idx]
        self._call_count += 1
        return FakeFetchResult(
            url=url,
            status_code=200,
            body=body,
            headers={"Content-Type": "application/vnd.apple.mpegurl"},
        )

    @property
    def call_count(self) -> int:
        return self._call_count


def _make_session(master: MasterPlaylist) -> SessionState:
    session = SessionState(
        session_id=make_session_id(master.url),
        url=master.url,
    )
    session.selected_renditions = select_renditions(master)
    return session


def _master() -> MasterPlaylist:
    return MasterPlaylist(
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


class TestLiveMonitorEndlist:
    @pytest.mark.asyncio
    async def test_stops_on_endlist(self) -> None:
        """A live stream that ends after 3 refreshes."""
        client = SequentialClient(MEDIA_URL, [
            _live_playlist(0, ["s0.ts", "s1.ts", "s2.ts"]),
            _live_playlist(1, ["s1.ts", "s2.ts", "s3.ts"]),
            _live_playlist(2, ["s2.ts", "s3.ts", "s4.ts"], endlist=True),
        ])
        master = _master()
        session = _make_session(master)

        await monitor_live(session, master, client)

        assert session.ended_at is not None
        assert client.call_count >= 3
        errors = [f for f in session.findings if f.severity == Severity.ERROR]
        assert len(errors) == 0

    @pytest.mark.asyncio
    async def test_three_refresh_clean(self) -> None:
        """Healthy live stream over 3 refreshes with no errors."""
        client = SequentialClient(MEDIA_URL, [
            _live_playlist(0, ["s0.ts", "s1.ts", "s2.ts"]),
            _live_playlist(1, ["s1.ts", "s2.ts", "s3.ts"]),
            _live_playlist(2, ["s2.ts", "s3.ts", "s4.ts"]),
            _live_playlist(3, ["s3.ts", "s4.ts", "s5.ts"], endlist=True),
        ])
        master = _master()
        session = _make_session(master)

        await monitor_live(session, master, client)

        assert session.ended_at is not None
        assert client.call_count >= 4
        errors = [f for f in session.findings if f.severity == Severity.ERROR]
        assert len(errors) == 0


class TestLiveMonitorContinuity:
    @pytest.mark.asyncio
    async def test_detects_sequence_regression(self) -> None:
        client = SequentialClient(MEDIA_URL, [
            _live_playlist(10, ["s10.ts", "s11.ts", "s12.ts"]),
            _live_playlist(5, ["x.ts", "y.ts", "z.ts"], endlist=True),
        ])
        master = _master()
        session = _make_session(master)

        await monitor_live(session, master, client)

        codes = {f.code for f in session.findings}
        assert FindingCode.CONTINUITY_MEDIA_SEQUENCE in codes

    @pytest.mark.asyncio
    async def test_detects_segment_mutation(self) -> None:
        client = SequentialClient(MEDIA_URL, [
            _live_playlist(0, ["s0.ts", "s1.ts", "s2.ts"]),
            # s1.ts should remain at seq 1 but we change it to MUTATED.ts
            "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:0\n"
            "#EXTINF:6.0,\ns0.ts\n#EXTINF:6.0,\nMUTATED.ts\n#EXTINF:6.0,\ns2.ts\n#EXT-X-ENDLIST\n",
        ])
        master = _master()
        session = _make_session(master)

        await monitor_live(session, master, client)

        codes = {f.code for f in session.findings}
        assert FindingCode.CONTINUITY_SEGMENT_STABILITY in codes


class TestLiveMonitorLimit:
    @pytest.mark.asyncio
    async def test_limit_enforcement(self) -> None:
        """A never-ending stream is stopped by the time limit."""
        never_ending = _live_playlist(0, ["s0.ts", "s1.ts"], target=1)
        client = SequentialClient(MEDIA_URL, [never_ending])
        master = _master()
        session = _make_session(master)

        await monitor_live(session, master, client, limit_seconds=0.5)

        assert session.ended_at is not None


class TestLiveMonitorCancellation:
    @pytest.mark.asyncio
    async def test_ctrl_c_handling(self) -> None:
        """Cancelling the task should produce a partial report."""
        never_ending = _live_playlist(0, ["s0.ts", "s1.ts"], target=1)
        client = SequentialClient(MEDIA_URL, [never_ending])
        master = _master()
        session = _make_session(master)

        task = asyncio.create_task(
            monitor_live(session, master, client)
        )
        await asyncio.sleep(0.3)
        task.cancel()

        try:
            await task
        except asyncio.CancelledError:
            pass

        assert session.ended_at is not None

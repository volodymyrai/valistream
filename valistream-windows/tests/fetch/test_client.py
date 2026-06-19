"""Tests for HLSClient — HTTP fetch with retry and timeout."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import aiohttp
import pytest
from yarl import URL

from valistream.fetch.client import USER_AGENT, HLSClient

MASTER_URL = "http://example.com/master.m3u8"
MASTER_BODY = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1280000\nlow.m3u8\n"


def _make_response(
    url: str = MASTER_URL,
    status: int = 200,
    body: str = MASTER_BODY,
    headers: dict[str, str] | None = None,
) -> MagicMock:
    """Build a mock aiohttp response usable as an async context manager."""
    resp = AsyncMock()
    resp.status = status
    resp.url = URL(url)
    resp.text = AsyncMock(return_value=body)
    resp.headers = headers or {"Content-Type": "application/vnd.apple.mpegurl"}

    cm = AsyncMock()
    cm.__aenter__ = AsyncMock(return_value=resp)
    cm.__aexit__ = AsyncMock(return_value=False)
    return cm


class TestHLSClientFetch:
    @pytest.mark.asyncio
    async def test_fetch_200(self) -> None:
        mock_cm = _make_response()

        with patch.object(aiohttp.ClientSession, "get", return_value=mock_cm):
            async with HLSClient() as client:
                result = await client.fetch(MASTER_URL)

        assert result.status_code == 200
        assert result.body == MASTER_BODY
        assert result.ok is True
        assert result.url == MASTER_URL
        assert result.response_time_ms >= 0

    @pytest.mark.asyncio
    async def test_fetch_404(self) -> None:
        mock_cm = _make_response(status=404, body="Not Found")

        with patch.object(aiohttp.ClientSession, "get", return_value=mock_cm):
            async with HLSClient() as client:
                result = await client.fetch(MASTER_URL)

        assert result.status_code == 404
        assert result.ok is False

    @pytest.mark.asyncio
    async def test_retry_on_503_then_success(self) -> None:
        call_count = 0

        def side_effect(*args: object, **kwargs: object) -> MagicMock:
            nonlocal call_count
            call_count += 1
            if call_count <= 2:
                return _make_response(status=503, body="")
            return _make_response(status=200)

        with patch.object(aiohttp.ClientSession, "get", side_effect=side_effect):
            async with HLSClient(backoff_base=0.01) as client:
                result = await client.fetch(MASTER_URL)

        assert result.status_code == 200
        assert result.body == MASTER_BODY
        assert call_count == 3

    @pytest.mark.asyncio
    async def test_retry_on_502_exhausted(self) -> None:
        mock_cm = _make_response(status=502, body="Bad Gateway")

        with patch.object(aiohttp.ClientSession, "get", return_value=mock_cm):
            async with HLSClient(max_retries=3, backoff_base=0.01) as client:
                result = await client.fetch(MASTER_URL)

        assert result.status_code == 502
        assert result.ok is False

    @pytest.mark.asyncio
    async def test_retry_on_504_then_success(self) -> None:
        call_count = 0

        def side_effect(*args: object, **kwargs: object) -> MagicMock:
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return _make_response(status=504, body="")
            return _make_response(status=200)

        with patch.object(aiohttp.ClientSession, "get", side_effect=side_effect):
            async with HLSClient(backoff_base=0.01) as client:
                result = await client.fetch(MASTER_URL)

        assert result.status_code == 200
        assert call_count == 2

    @pytest.mark.asyncio
    async def test_no_retry_on_400(self) -> None:
        call_count = 0

        def side_effect(*args: object, **kwargs: object) -> MagicMock:
            nonlocal call_count
            call_count += 1
            return _make_response(status=400, body="Bad Request")

        with patch.object(aiohttp.ClientSession, "get", side_effect=side_effect):
            async with HLSClient(backoff_base=0.01) as client:
                result = await client.fetch(MASTER_URL)

        assert result.status_code == 400
        assert call_count == 1

    @pytest.mark.asyncio
    async def test_connection_error_returns_status_zero(self) -> None:
        with patch.object(
            aiohttp.ClientSession,
            "get",
            side_effect=aiohttp.ClientConnectionError("Connection refused"),
        ):
            async with HLSClient(max_retries=3, backoff_base=0.01) as client:
                result = await client.fetch(MASTER_URL)

        assert result.status_code == 0
        assert result.ok is False
        assert result.body == ""

    @pytest.mark.asyncio
    async def test_timeout_error_returns_status_zero(self) -> None:
        import asyncio

        with patch.object(
            aiohttp.ClientSession,
            "get",
            side_effect=asyncio.TimeoutError(),
        ):
            async with HLSClient(max_retries=0, backoff_base=0.01) as client:
                result = await client.fetch(MASTER_URL)

        assert result.status_code == 0
        assert result.ok is False

    @pytest.mark.asyncio
    async def test_user_agent_header(self) -> None:
        async with HLSClient() as client:
            session = await client._get_session()
            assert session.headers.get("User-Agent") == USER_AGENT

    @pytest.mark.asyncio
    async def test_redirect_captured(self) -> None:
        redirect_url = "http://cdn.example.com/master.m3u8"
        mock_cm = _make_response(url=redirect_url)

        with patch.object(aiohttp.ClientSession, "get", return_value=mock_cm):
            async with HLSClient() as client:
                result = await client.fetch(MASTER_URL)

        assert result.url == MASTER_URL
        assert result.redirected_url == redirect_url
        assert result.final_url == redirect_url

    @pytest.mark.asyncio
    async def test_no_redirect_when_url_unchanged(self) -> None:
        mock_cm = _make_response(url=MASTER_URL)

        with patch.object(aiohttp.ClientSession, "get", return_value=mock_cm):
            async with HLSClient() as client:
                result = await client.fetch(MASTER_URL)

        assert result.redirected_url is None
        assert result.final_url == MASTER_URL

    @pytest.mark.asyncio
    async def test_context_manager_closes_session(self) -> None:
        mock_cm = _make_response()

        with patch.object(aiohttp.ClientSession, "get", return_value=mock_cm):
            client = HLSClient()
            async with client:
                await client.fetch(MASTER_URL)
                session = client._session
                assert session is not None
                assert not session.closed

        assert session is not None
        assert session.closed

    @pytest.mark.asyncio
    async def test_headers_captured(self) -> None:
        mock_cm = _make_response(
            headers={"Content-Type": "application/vnd.apple.mpegurl", "X-Custom": "test"},
        )

        with patch.object(aiohttp.ClientSession, "get", return_value=mock_cm):
            async with HLSClient() as client:
                result = await client.fetch(MASTER_URL)

        assert result.headers["Content-Type"] == "application/vnd.apple.mpegurl"
        assert result.headers["X-Custom"] == "test"


class TestHLSClientConfig:
    @pytest.mark.asyncio
    async def test_custom_timeouts(self) -> None:
        client = HLSClient(connect_timeout=5.0, total_timeout=15.0)
        assert client._connect_timeout == 5.0
        assert client._total_timeout == 15.0
        await client.close()

    @pytest.mark.asyncio
    async def test_custom_retry_params(self) -> None:
        client = HLSClient(max_retries=5, backoff_base=2.0)
        assert client._max_retries == 5
        assert client._backoff_base == 2.0
        await client.close()

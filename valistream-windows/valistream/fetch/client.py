"""aiohttp-based HTTP client with retry, timeout, and header capture."""

from __future__ import annotations

import time
from typing import TYPE_CHECKING

import aiohttp

from valistream import __version__
from valistream.fetch.result import FetchResult

if TYPE_CHECKING:
    from types import TracebackType

USER_AGENT = f"valistream/{__version__} (Windows)"

_TRANSIENT_STATUS_CODES = frozenset({502, 503, 504})

_DEFAULT_CONNECT_TIMEOUT_S = 10.0
_DEFAULT_TOTAL_TIMEOUT_S = 30.0
_DEFAULT_MAX_RETRIES = 3
_DEFAULT_BACKOFF_BASE_S = 1.0


class HLSClient:
    """Async HTTP client for fetching HLS playlists."""

    def __init__(
        self,
        *,
        connect_timeout: float = _DEFAULT_CONNECT_TIMEOUT_S,
        total_timeout: float = _DEFAULT_TOTAL_TIMEOUT_S,
        max_retries: int = _DEFAULT_MAX_RETRIES,
        backoff_base: float = _DEFAULT_BACKOFF_BASE_S,
    ) -> None:
        self._connect_timeout = connect_timeout
        self._total_timeout = total_timeout
        self._max_retries = max_retries
        self._backoff_base = backoff_base
        self._session: aiohttp.ClientSession | None = None

    async def _get_session(self) -> aiohttp.ClientSession:
        if self._session is None or self._session.closed:
            timeout = aiohttp.ClientTimeout(
                connect=self._connect_timeout,
                total=self._total_timeout,
            )
            self._session = aiohttp.ClientSession(
                timeout=timeout,
                headers={"User-Agent": USER_AGENT},
            )
        return self._session

    async def fetch(self, url: str) -> FetchResult:
        """Fetch a URL, retrying on transient errors with exponential backoff."""
        import asyncio

        session = await self._get_session()
        last_exception: BaseException | None = None

        for attempt in range(self._max_retries + 1):
            if attempt > 0:
                delay = self._backoff_base * (2 ** (attempt - 1))
                await asyncio.sleep(delay)

            start = time.monotonic()
            try:
                async with session.get(url, allow_redirects=True) as resp:
                    body = await resp.text()
                    response_time_ms = (time.monotonic() - start) * 1000

                    headers = {k: v for k, v in resp.headers.items()}
                    redirected_url = str(resp.url) if str(resp.url) != url else None

                    result = FetchResult(
                        url=url,
                        status_code=resp.status,
                        body=body,
                        headers=headers,
                        response_time_ms=response_time_ms,
                        redirected_url=redirected_url,
                    )

                    if resp.status in _TRANSIENT_STATUS_CODES and attempt < self._max_retries:
                        last_exception = None
                        continue

                    return result

            except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
                last_exception = exc
                if attempt >= self._max_retries:
                    response_time_ms = (time.monotonic() - start) * 1000
                    return FetchResult(
                        url=url,
                        status_code=0,
                        body="",
                        response_time_ms=response_time_ms,
                    )

        response_time_ms = (time.monotonic() - start) * 1000
        return FetchResult(
            url=url,
            status_code=0,
            body="",
            response_time_ms=response_time_ms,
        )

    async def close(self) -> None:
        if self._session is not None and not self._session.closed:
            await self._session.close()

    async def __aenter__(self) -> HLSClient:
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: TracebackType | None,
    ) -> None:
        await self.close()

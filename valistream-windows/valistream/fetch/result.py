"""FetchResult dataclass — HTTP response with body, status, headers, and timing."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class FetchResult:
    """Result of an HTTP playlist fetch."""

    url: str
    status_code: int
    body: str
    headers: dict[str, str] = field(default_factory=dict)
    response_time_ms: float = 0.0
    redirected_url: str | None = None

    @property
    def ok(self) -> bool:
        return 200 <= self.status_code < 400

    @property
    def final_url(self) -> str:
        return self.redirected_url or self.url

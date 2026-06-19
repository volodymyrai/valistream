"""Tests for FetchResult dataclass."""

from valistream.fetch.result import FetchResult


class TestFetchResult:
    def test_ok_for_200(self) -> None:
        r = FetchResult(url="http://example.com/master.m3u8", status_code=200, body="#EXTM3U")
        assert r.ok is True

    def test_ok_for_301(self) -> None:
        r = FetchResult(url="http://example.com/a.m3u8", status_code=301, body="")
        assert r.ok is True

    def test_not_ok_for_404(self) -> None:
        r = FetchResult(url="http://example.com/a.m3u8", status_code=404, body="")
        assert r.ok is False

    def test_not_ok_for_500(self) -> None:
        r = FetchResult(url="http://example.com/a.m3u8", status_code=500, body="")
        assert r.ok is False

    def test_not_ok_for_zero(self) -> None:
        r = FetchResult(url="http://example.com/a.m3u8", status_code=0, body="")
        assert r.ok is False

    def test_final_url_without_redirect(self) -> None:
        r = FetchResult(url="http://example.com/a.m3u8", status_code=200, body="")
        assert r.final_url == "http://example.com/a.m3u8"

    def test_final_url_with_redirect(self) -> None:
        r = FetchResult(
            url="http://example.com/a.m3u8",
            status_code=200,
            body="",
            redirected_url="http://cdn.example.com/a.m3u8",
        )
        assert r.final_url == "http://cdn.example.com/a.m3u8"

    def test_frozen(self) -> None:
        r = FetchResult(url="http://example.com/a.m3u8", status_code=200, body="")
        try:
            r.url = "other"  # type: ignore[misc]
            raise AssertionError("Should be frozen")
        except AttributeError:
            pass

    def test_defaults(self) -> None:
        r = FetchResult(url="http://example.com/a.m3u8", status_code=200, body="x")
        assert r.headers == {}
        assert r.response_time_ms == 0.0
        assert r.redirected_url is None

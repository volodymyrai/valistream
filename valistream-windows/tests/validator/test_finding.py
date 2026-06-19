"""Tests for Finding model and enums."""

from valistream.validator.finding import Finding, FindingCode, Severity
from valistream.validator import spec_catalog


class TestSeverity:
    def test_values(self) -> None:
        assert Severity.ERROR.value == "error"
        assert Severity.WARNING.value == "warning"
        assert Severity.INFO.value == "info"

    def test_str_comparison(self) -> None:
        assert Severity.ERROR == "error"


class TestFindingCode:
    def test_rfc_codes_exist(self) -> None:
        assert FindingCode.RFC8216_4_3_3_1.value == "RFC8216.4.3.3.1"
        assert FindingCode.RFC8216_4_3_4_2_BANDWIDTH.value == "RFC8216.4.3.4.2-BANDWIDTH"

    def test_apple_codes_exist(self) -> None:
        assert FindingCode.APPLE_CODECS.value == "APPLE.codecs"
        assert FindingCode.APPLE_TARGET_DURATION.value == "APPLE.target-duration"

    def test_continuity_codes_exist(self) -> None:
        assert FindingCode.CONTINUITY_MEDIA_SEQUENCE.value == "TOOL.continuity.media-sequence"


class TestFinding:
    def test_required_fields(self) -> None:
        f = Finding(
            code=FindingCode.DELIVERY_CONTENT_TYPE,
            severity=Severity.WARNING,
            message="test",
        )
        assert f.code == FindingCode.DELIVERY_CONTENT_TYPE
        assert f.severity == Severity.WARNING
        assert f.message == "test"
        assert f.spec_ref is None
        assert f.playlist_url is None
        assert f.line is None
        assert f.details == {}

    def test_all_fields(self) -> None:
        f = Finding(
            code=FindingCode.RFC8216_4_3_3_1_DURATION,
            severity=Severity.ERROR,
            message="too long",
            playlist_url="http://example.com/playlist.m3u8",
            line=5,
            details={"duration": 12.0, "targetDuration": 10.0},
        )
        assert f.spec_ref == "RFC 8216 §4.3.3.1"
        assert f.details["duration"] == 12.0

    def test_spec_ref_auto_population(self) -> None:
        assert spec_catalog.reference("RFC8216.4.3.3.1") == "RFC 8216 §4.3.3.1"
        assert spec_catalog.reference("RFC8216.4.3.4.2-BANDWIDTH") == "RFC 8216 §4.3.4.2"
        assert spec_catalog.reference("APPLE.codecs") == "HLS Authoring §9.1"
        assert spec_catalog.reference("TOOL.continuity.media-sequence") == "RFC 8216 §6.2.2"
        assert spec_catalog.reference("TOOL.delivery.content-type") is None
        assert spec_catalog.reference("APPLE.target-duration") is None

    def test_frozen(self) -> None:
        f = Finding(code=FindingCode.RFC8216_4_3_3_1, severity=Severity.ERROR, message="x")
        try:
            f.message = "y"  # type: ignore[misc]
            assert False, "should be frozen"
        except AttributeError:
            pass

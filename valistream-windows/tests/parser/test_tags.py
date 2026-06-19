"""Tests for tag attribute parsing."""

from valistream.parser.tags import parse_attribute_list


class TestParseAttributeList:
    def test_simple_unquoted(self) -> None:
        result = parse_attribute_list("BANDWIDTH=1280000,RESOLUTION=1280x720")
        assert result == {"BANDWIDTH": "1280000", "RESOLUTION": "1280x720"}

    def test_quoted_values(self) -> None:
        result = parse_attribute_list('CODECS="avc1.4d401f,mp4a.40.2",BANDWIDTH=1280000')
        assert result["CODECS"] == "avc1.4d401f,mp4a.40.2"
        assert result["BANDWIDTH"] == "1280000"

    def test_uri_quoted(self) -> None:
        result = parse_attribute_list('METHOD=AES-128,URI="https://key.example.com/key.bin",IV=0x1234')
        assert result["METHOD"] == "AES-128"
        assert result["URI"] == "https://key.example.com/key.bin"
        assert result["IV"] == "0x1234"

    def test_empty_string(self) -> None:
        assert parse_attribute_list("") == {}

    def test_group_id(self) -> None:
        result = parse_attribute_list('TYPE=AUDIO,GROUP-ID="audio",NAME="English",LANGUAGE="en"')
        assert result["TYPE"] == "AUDIO"
        assert result["GROUP-ID"] == "audio"
        assert result["NAME"] == "English"
        assert result["LANGUAGE"] == "en"

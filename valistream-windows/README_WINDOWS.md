# valistream (Python)

HLS stream validator — validates and monitors HLS playlists against RFC 8216 and Apple HLS authoring rules.

Python port of [valistream](https://github.com/volodymyrai/valistream) (originally macOS/Swift).

## Installation

### From source (recommended; compatible with all platforms)

```powershell
git clone https://github.com/volodymyrai/valistream.git
cd valistream
python -m venv .venv
.venv\Scripts\activate
pip install -e ".[dev]"
```


## Quick Start

```powershell
# Verify installation
valistream --version
valistream --help

# Validate a VOD playlist
valistream "https://example.com/stream/master.m3u8"

# Monitor a live stream for 15 minutes
valistream "https://example.com/live/master.m3u8" --limit 15m

# JSON output for CI/scripting
valistream "https://example.com/stream/master.m3u8" --json --non-interactive

# Pre-select specific renditions
valistream "https://example.com/stream/master.m3u8" --preselect "1080p,720p"
```

## CLI Usage

```
valistream <url> [OPTIONS]

Arguments:
  <url>                          HTTP/HTTPS URL of a master or media playlist

Options:
  --limit <limit>                Live session time limit (90s, 15m, 24h)
  --preselect <patterns>         Pre-select renditions (comma-separated patterns)
  --select                       Interactive multi-select checklist (TTY required)
  --non-interactive              Never prompt; process all renditions
  --output-dir <path>            Parent directory for session folders
  --json                         Machine output: findings as JSON Lines on stdout
  --quiet                        Suppress live status; findings and summary only
  --verbose                      Extended detail: raw timestamps, all HTTP headers
  --no-color                     Disable terminal color output (also: NO_COLOR env var)
  --version                      Show version
  -h, --help                     Show help
```

## Output

Each session creates a timestamped directory under `~/.valistream/sessions/` (or `--output-dir`):

```
20260618T120000_example-com-master/
  findings.jsonl      # One JSON object per finding, appended in real time
  report.json         # Machine-readable session report (schema v1)
  report.md           # Human-readable Markdown report
  playlists/          # Playlist snapshots (live streams only)
    video-720p/
      video-720p_000100.m3u8
      video-720p_000100.meta.json
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Validation passed (no errors, warnings are OK) |
| 1 | Validation found errors, or fetch/parse failure |
| 2 | Invalid CLI arguments |
| 130 | Interrupted (Ctrl+C) |

## Testing URLs

Real HLS live streams are available in `hls_channels_AT.json` (root folder). Each entry with a non-null `liveUrl` value is a usable test URL. Recommended starting point: **NRK2**.

> **Note:** URLs contain time-limited tokens and may expire.

## Requirements

- **Standalone EXE:** Windows 10/11 (x64), no other dependencies
- **pip install:** Python 3.11+, Windows 10/11

## Development

```powershell
# Run tests
pytest

# Type checking
mypy valistream

# Linting
ruff check valistream

# Coverage
coverage run -m pytest
coverage report

# Build standalone EXE
pip install pyinstaller>=6.0
pyinstaller valistream.spec --noconfirm
# Output: dist/valistream.exe
```

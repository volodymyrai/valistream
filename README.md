# valistream

HLS stream validator — validates master and media playlists against RFC 8216 and Apple HLS authoring rules.

## Usage

```
valistream <url> [options]
```

`<url>` must be an `http://` or `https://` URL to a master playlist (or a media playlist, which is auto-detected).

## Options

| Option | Description |
|--------|-------------|
| `--output <dir>` | Parent directory for the per-session output folder. Defaults to `~/.valistream/sessions/`. Relative paths are resolved to absolute. |
| `--limit <duration>` | Cap a live session — e.g. `90s`, `15m`, `24h`. |
| `--select <patterns>` | Comma-separated substrings to pre-select playlists (matches id, group, name, or URL). Skips the interactive prompt. |
| `--all` | Select all playlists and skip the interactive prompt. |
| `--non-interactive` | Never prompt; implies `--all` unless `--select` is given. |
| `--verbose` | Extended output: per-request timings and diagnostic detail. |
| `--quiet` | Findings and errors only; no status or progress. |
| `--no-color` | Force plain text output (also honoured via `NO_COLOR` env var or `TERM=dumb`). |
| `--json` | Machine-readable output: status objects as JSON Lines on stdout. |

`--quiet` and `--verbose` are mutually exclusive.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Validated — no findings. |
| `1` | Validated — one or more findings present. |
| `2` | Usage or pre-condition error (bad URL, unwritable output dir, …). |
| `3` | Operational error (network failure, unreadable playlist, …). |
| `130` | Forced interrupt (second Ctrl-C during graceful shutdown). |

## Output

Each run creates a unique session folder under `--output` (default `~/.valistream/sessions/<sessionID>/`). The path is printed at startup before any network activity. The folder contains:

- `report.json` — machine-readable findings (schema v1, compatible with feature 001).
- `report.md` — human-readable Markdown with an aliases legend and findings grouped by severity and category.
- `findings.jsonl` — append-only JSONL log of findings (durable on interrupt).
- `playlists/` — fetched playlist snapshots with `.meta.json` sidecars.

## Interactive playlist selection

On an interactive TTY without `--select` or `--all`, valistream shows a multi-select prompt after the initial validation. Arrow keys navigate, Space toggles, Enter confirms, `a` toggles all.

The prompt is skipped automatically when:
- There is no interactive terminal (no TTY, piped, scripted).
- `--all` or `--non-interactive` is passed.
- `--select <patterns>` is passed.

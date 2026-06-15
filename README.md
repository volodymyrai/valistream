# valistream

![Version](https://img.shields.io/badge/version-0.4.0-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)

Validates and monitors HLS streams against RFC 8216 and Apple HLS authoring rules. 

📥 Fetches every master/media-playlist → **validates agains HLS specs**

📺 Follows Live stream playlist refresh logic → **validates continuity**

📝 Writes whole session logs and all artifacts to disk for **evidence**

🗒️ Generates full session **report**

---

## Quick start

Download `valistream-cli.zip` from latest Release

### On MacOS

```bash
./valistream "<.m3u8 URL here>"

or 

./valistream --help # for more options
```

### On Windows

_Not yet supported 🤞_

## Generated artifacts

Every run creates a timestamped session folder under `--output`
(default `~/.valistream/sessions/<sessionID>/`)

| File | Description |
|------|-------------|
| `report.md` | Human-readable Markdown: incident timeline, findings by severity, playlist information block, legend. |
| `report.json` | Machine-readable findings (schema v1). |
| `findings.jsonl` | Append-only JSON Lines log. |
| `playlists/<id>/NNNNNN.m3u8` | Fetched playlist snapshot. `<id>` is a stable alias (e.g. `video-1080p`, `audio-en`). |
| `playlists/<id>/NNNNNN.meta.json` | Sidecar with fetch metadata (URL, HTTP status, timing, refresh index). |

---

## Links

- [RFC 8216 — HTTP Live Streaming](https://datatracker.ietf.org/doc/html/rfc8216)
- [Apple HLS Authoring Specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices)

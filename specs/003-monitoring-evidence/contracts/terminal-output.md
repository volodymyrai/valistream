# Contract: Terminal Output (delta over 001/002)

Normative for US1/US2's on-screen behavior. Inherits the 002 styling gate (color iff TTY ∧ ¬NO_COLOR ∧
¬`--no-color` ∧ TERM≠dumb; severity also in text; no control bytes when not a TTY).

## Invariant — zero raw URLs (SC-003)

At **every** verbosity tier including `--verbose`, the terminal body MUST refer to playlists by **ID**
only. Full URLs appear **only** in the start-of-session roster. The current
`StatusRenderer.renderFinding` prints `finding.resource.absoluteString` — this MUST be replaced by the
ID + evidence form below.

## Roster (FR-011, normal+)

Printed once, after the output folder line and before any fetch (driven by
`SessionEvent.rosterReady`). One row per discovered playlist: `<id>   <full-url>   (<role>[, attrs])`.

```
master       https://…/master.m3u8            (master)
1080p_avc1   https://…/v/1080/playlist.m3u8   (video, 1920x1080, avc1.640028)
audio_en     https://…/a/en/playlist.m3u8     (audio, en)
```

## Heartbeat (FR-013/014, normal+, TTY)

In-place line: `⠼ <id> · refresh <sessionRefreshTotal> · <elapsed>`.
- `<sessionRefreshTotal>` is **session-wide monotonic** (D7) — never decreases, equals refreshes
  performed (SC-004).
- Stray keystrokes (Enter/arrows) MUST NOT corrupt the region nor move the count backward — enforced by
  `LiveInputGuard` termios echo suppression (D8), restored on every exit path.
- Non-TTY: no in-place region; plain per-refresh lines only.

## Per-refresh status line (normal+)

One discrete line per refresh (scrolls on a TTY in addition to the heartbeat; one plain line per
refresh when piped), ending in a status summary:
- no findings → `1080p_avc1_12 — OK`
- otherwise → `1080p_avc1_12 — 2 WARN, 1 ERROR`, with each WARN/ERROR (and its evidence) printed
  **indented beneath** this line.

## Finding lines with evidence (FR-004/006/009; US1)

| Kind | Form |
|------|------|
| ERROR | `ERROR <id>_<n> <msg> · evidence: playlists/<id>/<id>_<n>.m3u8` |
| WARN | `WARN <id>_<n> <msg> · evidence: playlists/<id>/<id>_<n>.m3u8` |
| Continuity | `WARN <id> discontinuity <id>_<n-1>↔_<n> · evidence: …/<id>_<n-1>.m3u8, …/<id>_<n>.m3u8` |
| Evidence unavailable | `WARN <id>_<n> — no body captured for <id>` (ID/label, **never** a URL) |

Evidence paths come from the pure `EvidenceResolver` (see `evidence-and-ids.md`). Findings print at
**all** tiers (quiet/normal/verbose).

## Output message catalog (FR-015a/b)

✓ = emitted at that tier. Supersets: quiet ⊆ normal ⊆ verbose. Tiers affect on-screen output only —
never report files or exit codes (FR-001).

| Message | quiet | normal | verbose |
|---------|:-----:|:------:|:-------:|
| Version / help (on demand) | ✓ | ✓ | ✓ |
| Fatal usage/IO error (stderr, exit 2) | ✓ | ✓ | ✓ |
| Output folder announced (absolute) | | ✓ | ✓ |
| Session roster (ID → URL + role) | | ✓ | ✓ |
| Selection checklist (`--select` + TTY) | interactive | interactive | interactive |
| `--select` non-TTY fallback notice | ✓ | ✓ | ✓ |
| Session-start milestone | | ✓ | ✓ |
| In-place heartbeat (TTY) | | ✓ | ✓ |
| Per-refresh status line | | ✓ | ✓ |
| ERROR finding (+ evidence) | ✓ | ✓ | ✓ |
| WARN finding (+ evidence) | ✓ | ✓ | ✓ |
| Continuity finding (two files) | ✓ | ✓ | ✓ |
| Evidence-unavailable notice | ✓ | ✓ | ✓ |
| INFO milestone | | ✓ | ✓ |
| Fetch intent | | | ✓ |
| Fetch result (HTTP status; ms; bytes) | | | ✓ |
| Validation outcome — per playlist (incl. OK) | | | ✓ |
| Validation outcome — per rule (incl. OK) | | | ✓ |
| Archive write (stored file) | | | ✓ |
| Refresh scheduling / cadence (drift) | | | ✓ |
| Continuity comparison trace | | | ✓ |
| Rendition lifecycle (added/dropped) | | | ✓ |
| Shutdown notice | ✓ | ✓ | ✓ |
| Final summary (counts + paths) | ✓ | ✓ | ✓ |

**Quiet** = findings (each with evidence) + evidence-unavailable notices + `--select` non-TTY notice +
fatal errors + final summary only. No roster, heartbeat, per-refresh line, INFO, or traces.

**Verbose distinctness** (SC-005): verbose MUST add ≥ 5 categories absent at normal (fetch intent,
fetch result, per-playlist/per-rule validation, archive writes, refresh cadence, continuity compares) —
not a near-copy of normal. All verbose lines are **ID-based** (SC-003).

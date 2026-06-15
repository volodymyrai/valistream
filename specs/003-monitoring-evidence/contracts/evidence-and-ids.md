# Contract: Evidence & Playlist IDs (delta over 001/002)

Normative for US1 (evidence) and US3 (IDs). All of this is **presentation + archive naming**; the
structured JSON report schema/values are FROZEN (FR-002).

## Playlist ID grammar (FR-016–020)

| Role | ID | Rule |
|------|----|----|
| master | `master` | exact (FR-017) |
| video | `<height>p_<codecs>` | pixel height of `RESOLUTION` + `p`, then `<codecs>`; no `variant_` prefix (FR-018) |
| audio | `audio_<slug(LANGUAGE)>` | append `_<slug(NAME)>` on same-language collision; `NAME` alone if no `LANGUAGE` |
| subtitles | `subs_<slug(LANGUAGE\|NAME)>` | same rule as audio |
| I-frame | `iframe_<height>p` | role-based |
| fallback | role + ordinal | when attributes needed for the preferred ID are absent (FR-020) |

- `<codecs>`: **every** codec in `CODECS`, each trimmed to its sample-entry/fourCC (drop from first
  `.`), joined in advertised order by `-`. `avc1.640028,mp4a.40.2` → `avc1-mp4a`; video-only → `avc1`.
- `slug` = lowercased; non-alphanumeric runs collapse to `_`.
- `_` is the **reserved** field separator — MUST NOT appear inside a field value.
- **Determinism** (FR-019): same stream → same IDs across runs; stable within a session; unique within
  a session (residual collision → deterministic numeric suffix). Charset `[a-z0-9_-]` (filesystem-safe).
- Same ID used **everywhere** the playlist appears (roster, heartbeat, findings, report body, legend,
  archive folder) and across every refresh/report update (SC-006/007).

## Snapshot label (FR-018a)

`<id>_<n>` where `<n>` is the **0-based per-playlist** refresh index (first fetch `_0`). Used for:
continuity operands, single-snapshot findings, verbose traces, per-refresh status line, **and** the
archive file name. The bare `<id>` is used for identity/display. VOD/single-fetch → only `_0`.

## Archive layout (FR-029)

```
<sessionFolder>/playlists/<id>/<id>_<n>.m3u8        # snapshot body
<sessionFolder>/playlists/<id>/<id>_<n>.meta.json   # sidecar (pretty-printed, FR-026)
```

Refines 001's `playlists/<id>/NNNNNN.m3u8`. The per-playlist subdir is kept; the file base name is the
snapshot label so any evidence file is self-identifying when attached to a ticket. Only the
artifact-index path **values** change — schema FROZEN (FR-002).

## Evidence resolution (FR-004–009)

A pure resolver maps a `Finding` → `EvidenceReference`:

| Finding | Result | Rendered |
|---------|--------|----------|
| single-snapshot (any non-continuity ERROR/WARN) | `.single("playlists/<id>/<id>_<n>.m3u8")` | one path |
| pairwise continuity (`category == .continuity`, except staleness) | `.pair("…/<id>_<n-1>.m3u8", "…/<id>_<n>.m3u8")` | previous and current paths (FR-006) |
| staleness (`ruleId == TOOL.staleness`) | `.pair("…/<id>_<b>.m3u8", "…/<id>_<n>.m3u8")` | last changed baseline `<b>` and threshold-confirming snapshot `<n>` |
| producing fetch failed (no captured body) | `.unavailable(<id>)` | `no body captured for <id>` — ID/label, never a URL (FR-009) |

- **Join key is the finding's `resource` URL**, matched against the archive's `IndexEntry.url`; `<n>` is
  the finding's `refreshIndex`. The path is deterministic from `<id>` + `<n>`.
- Staleness keeps the same two-reference contract, but its first operand is the last snapshot that
  changed, not necessarily `<n-1>`. Intermediate unchanged retries are not evidence operands.
- **`<id>` ≠ `playlists[].id`** (the frozen JSON field). Never use `playlists[].id` for the join.
- **Unavailable placeholder ID** (when failure prevented ID assignment): `master` for the master,
  else role+ordinal (FR-020) — so SC-003 holds unconditionally.
- **Continuity, one snapshot missing** (edge case): reference the available file; clearly note the
  missing one.
- Evidence is **whole-file only** — no in-file line/segment locus (final clarification).
- Terminal and report MUST render the **same** reference(s) (FR-005).

## Recovery from the structured report (FR-008, no schema change)

A consumer recovers evidence using existing fields only:
1. Take the finding's `resource` (URL) and `refreshIndex` (`n`).
2. Find the artifact-index entries whose `url == resource`; the snapshot is the one whose `bodyPath`
   ends `_<n>.m3u8` (equivalently, recompute `playlists/<id>/<id>_<n>.m3u8`).
3. Continuity → also take `n-1`.

No field is added, removed, renamed, retyped, or repurposed (SC-009).

## Success criteria mapping

SC-001 (100% findings carry evidence; continuity exactly two) · SC-002 (open in < 15 s, no extra
lookup) · SC-003 (zero raw URLs in body) · SC-006/007 (ID uniqueness/stability + master/`<height>p_…`
forms).

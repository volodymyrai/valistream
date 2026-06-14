# Phase 1 Data Model: Reliable Monitoring and Evidence

This feature adds **presentation-layer** entities and renames archive artifacts. It introduces **no new
structured-report field** and changes **no** frozen type. The structured report's data model (schema,
fields, values incl. `playlists[].id`) is **FROZEN** from feature 001 and is intentionally absent here.

Legend: 🆕 new · ✏️ modified (additive/backward-compatible) · 🔒 frozen (shown for context, unchanged).

---

## Playlist ID (a.k.a. alias) ✏️ — `AliasRegistry` / `PlaylistAlias`

The short, deterministic, session-unique, **stable** label that stands in for a full URL throughout
terminal output and the report body. It is a **presentation** value and **does not appear in the
structured (JSON) report**.

| Field | Type | Notes |
|-------|------|-------|
| `alias` | `String` | the ID; grammar below |
| `url` | `URL` | the playlist's full URL (join key for evidence; appears only in roster/legend) |
| `role` | `AliasRole` | master / video / audio / subtitles / iframe / unknown |
| `attributes` | `[String: String]` | source attrs (`RESOLUTION`, `CODECS`, `LANGUAGE`, `NAME`, …) |

**Grammar** (FR-016–020):

| Role | ID form | Example |
|------|---------|---------|
| master | `master` | `master` |
| video | `<height>p_<codecs>` | `1080p_avc1`, `1080p_avc1-mp4a` |
| audio | `audio_<slug(LANGUAGE)>` (`_<slug(NAME)>` on same-lang collision; `NAME` if no `LANGUAGE`) | `audio_en`, `audio_en_commentary` |
| subtitles | `subs_<slug(LANGUAGE\|NAME)>` | `subs_en` |
| I-frame | `iframe_<height>p` | `iframe_720p` |
| fallback | role + ordinal (attributes missing) | `audio_1`, `video_1` |

**Derivation rules**
- `<codecs>` = **every** codec in `CODECS`, each trimmed to its sample-entry/fourCC (drop from the first
  `.`), joined in advertised order by `-`. `avc1.640028,mp4a.40.2` → `avc1-mp4a`.
- `slug` = lowercased; runs of non-alphanumeric collapsed to `_`.
- `_` is the **reserved field separator** and MUST NOT appear inside a field value.
- **Invariants** (FR-019): deterministic across runs of the same stream; stable within a session (same
  playlist keeps its ID across every refresh/report update); unique within a session (residual
  collisions → deterministic numeric suffix). Charset is `[a-z0-9_-]` only → filesystem-safe (D6).

**Lifecycle**: one `AliasRegistry` is owned by the `ValidationSession`, populated at discovery, and is
the single source of truth for the heartbeat, findings, report body/legend, **and** archive paths.

---

## Snapshot ID 🆕 — `SnapshotID` (pure formatter)

Identifies a **specific refresh** of a playlist.

| Concept | Form | Notes |
|---------|------|-------|
| label | `<id>_<n>` | `<n>` = 0-based per-playlist refresh index; first fetch `_0` |
| usage (indexed) | continuity operands `<id>_<n-1>`/`<id>_<n>`, single-snapshot findings, every verbose trace line, per-refresh status line, archive file name | a *specific* refresh |
| usage (bare `<id>`) | roster, legend, in-place heartbeat, ID assignment | identity/display |

VOD / single-fetch playlists only ever have `_0`. The label equals the archived file's base name (D6),
so evidence files are self-identifying.

---

## Evidence Reference 🆕 — `EvidenceReference` + `EvidenceResolver` (pure)

The exact archived on-disk file(s) that prove a finding.

```
EvidenceReference =
  | .single(path: String)                         // single-snapshot finding
  | .pair(older: String, newer: String)           // continuity finding (two consecutive snapshots)
  | .unavailable(id: String)                       // producing fetch failed — name by ID, never URL
```

- `path` form: relative archive path `playlists/<id>/<id>_<n>.m3u8` (FR-005/007), openable directly,
  copy-pasteable, viewer-agnostic. Whole-file only — **no** line/segment locus.
- **Resolver inputs**: a `Finding` (+ `resource: URL`, `refreshIndex: Int?`, `category`), the session
  `AliasRegistry` (URL → ID), and the archive's per-playlist refresh state / `artifactIndex` (capture
  check). **Join key is the URL**, never the frozen `playlists[].id`.
- **Selection**: `category == .continuity` → `.pair(<id>_<n-1>, <id>_<n>)`; else `.single(<id>_<n>)`;
  if no body was captured for `(url, n)` → `.unavailable(id)` (placeholder ID for pre-assignment
  failures: `master`, else role+ordinal). FR-004–009, SC-001/002.
- **Consumers**: `StatusRenderer` (terminal) and `SessionReportBuilder` (markdown) — identical output.

---

## Session Roster / Legend ✏️

The mapping of each playlist ID → full URL + role/attributes.

| Surface | When | Carrier |
|---------|------|---------|
| Roster | once at session start, before fetching (FR-011) | 🆕 `SessionEvent.rosterReady([RosterEntry])`, rendered at normal+ |
| Legend | in the report (FR-012) | `SessionReportBuilder` markdown (existing legend section, now ID-scheme) |

`RosterEntry = { id: String, url: URL, role: String /* + attrs summary */ }`. After the roster, **no**
full URL appears in the terminal body or report body at any tier (SC-003).

---

## Heartbeat / Live Status ✏️ — `ActivityProgress` (+ monotonic total)

The stable, in-place live-monitoring status region.

| Field | Type | Change |
|-------|------|--------|
| `activity` | `String` | (existing) descriptive, ID-based wording |
| `completed` | `Int` | (existing) |
| `total` | `Int?` | (existing) |
| `refreshes` | `Int?` | (existing) per-playlist context |
| `aliasInScope` | `String?` | (existing) current playlist ID |
| `sessionRefreshTotal` | `Int` | 🆕 **session-wide monotonic** refresh count (D7) — the displayed heartbeat number |

Display form: `⠼ <id> · refresh <sessionRefreshTotal> · <elapsed>`. The number is monotonic
non-decreasing and equals the actual number of refreshes performed (FR-013, SC-004). The counter lives
under the `ValidationSession` actor (data-race-free). Stray keystrokes never corrupt the region —
enforced by `LiveInputGuard` (termios echo suppression, CLI; D8), not by this model.

---

## Verbosity Level & Trace Events ✏️ / 🆕

`Verbosity` = quiet / normal / verbose (existing). Tier membership affects **on-screen output only** —
never report files or exit codes (FR-001/015a). Supersets: quiet ⊆ normal ⊆ verbose.

**Additive `SessionEvent` cases** (🆕, no JSON/exit impact):

| Case | Tier | Purpose |
|------|------|---------|
| `.rosterReady([RosterEntry])` | normal+ | start-of-session roster (FR-011) |
| `.refreshCompleted(playlistID:String, index:Int, errors:Int, warnings:Int)` | normal+ | per-refresh status line: `OK` or `x WARN, y ERROR` (catalog) |
| `.trace(TraceEvent)` | verbose | descriptive ID-based action trace (FR-015b) |

**`TraceEvent` 🆕** (rendered by pure `TraceFormatter` to category-prefixed, ID-based lines):

| Variant | Example line |
|---------|--------------|
| `.fetchIntent(snapshot)` | `Fetch: requesting playlist 1080p_avc1_5` |
| `.fetchResult(snapshot, status, ms, bytes)` | `Fetch: playlist 1080p_avc1_5 HTTP 200; 25ms; 1.3 kB` |
| `.validatedPlaylist(snapshot, outcome)` | `Validation: playlist 1080p_avc1_5 — OK` |
| `.validatedRule(snapshot, rule, outcome)` | `Validation: 1080p_avc1_5 rule TARGETDURATION — OK` |
| `.stored(snapshot, file)` | `Stored: playlist 1080p_avc1_5 → playlists/1080p_avc1/1080p_avc1_5.m3u8` |
| `.refreshScheduled(id, index, delay, drift)` | `Refresh: 1080p_avc1 refresh 13 in 6s (drift +0.2s)` |
| `.compared(newer, older, result)` | `Compare: 1080p_avc1_12↔_11 — continuous` |
| `.renditionLifecycle(master, change, id)` | `INFO master added rendition 1080p_avc1` |

See `contracts/terminal-output.md` for the full **Output message catalog** and exact tier matrix.

---

## Archive Artifacts ✏️ — `SessionArchive`

| Item | Before (001/002) | After (FR-029) |
|------|------------------|----------------|
| snapshot body | `playlists/<id>/NNNNNN.m3u8` | `playlists/<id>/<id>_<n>.m3u8` |
| snapshot sidecar | `playlists/<id>/NNNNNN.meta.json` | `playlists/<id>/<id>_<n>.meta.json` |
| `<id>` source | archive-ref string (`master`/`<role>-<i>`/`media`) | the real presentation ID from `AliasRegistry` |
| sidecar encoder | compact `Finding.jsonEncoder` | 🆕 `Finding.prettyJSONEncoder` (FR-026) |
| `IndexEntry` shape 🔒 | `{ requestId, url, bodyPath, metaPath }` | unchanged (only `bodyPath`/`metaPath` **values** change) |

---

## JSON Encoders ✏️ — `Finding`

| Encoder | Formatting | Used by |
|---------|-----------|---------|
| `Finding.jsonEncoder` (existing) 🔒 | `[.sortedKeys, .withoutEscapingSlashes]`, ISO-8601 | **`--json` NDJSON stream** (one compact object per line, FR-028) |
| `Finding.prettyJSONEncoder` 🆕 | same + `.prettyPrinted` | structured report file + `*.meta.json` sidecars (FR-026) |

`.sortedKeys` guarantees stable key ordering in both; pretty differs only by whitespace, so the report
still validates against the frozen schema (FR-027).

---

## Frozen, shown for context 🔒 (DO NOT MODIFY)

- `Finding` struct fields (`id, ruleId, source, severity, category, resource, location, refreshIndex,
  observedAt, message, context`) — evidence is derived from `resource` + `refreshIndex`, **no new
  field**.
- Structured `Report` schema + `PlaylistInfo.id` value — frozen (FR-002). `PlaylistInfo.id` ≠
  presentation ID ≠ archive folder name.
- Exit codes 0/1/2/3 + 130; rule set / rule IDs / finding catalog.

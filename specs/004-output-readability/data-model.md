# Phase 1 Data Model: Readable Output and Onboarding (004)

**Feature**: 004-output-readability | **Date**: 2026-06-15 | **Spec**: [spec.md](./spec.md) ·
[research.md](./research.md)

Feature 004 is presentation-centric. It introduces **no** new validation data and changes **no** frozen
machine-readable structure (FR-002/FR-028). The entities below are presentation/recording models plus one
minimal additive metadata surface on the playlist model. Existing types are noted as **reuse**.

All new Core types are `Sendable`, live in `ValistreamCore` (Foundation-only), and are pure value types
unless stated. Filesystem locations use repo-root paths (see plan.md → Project Structure).

---

## 1. Event timing

### `TimestampedEvent` (new — envelope)
Wraps each emitted event with its **occurrence** instant so terminal and report derive from the same value
(D1, FR-008c, FR-025e, SC-003c).

| Field | Type | Notes |
|---|---|---|
| `at` | `Date` | Captured at occurrence via the session's injected `now` clock |
| `event` | `SessionEvent` | The existing event (case shapes unchanged) |

- **Validation**: `at` is monotonic-friendly but represents wall time; the renderer MUST NOT re-stamp.
- **Reuse**: `Finding.observedAt: Date` already carries finding occurrence — finding events use it as `at`.

### `SessionEvent` (reuse + additive cases)
Existing: `stateChanged`, `streamClassified`, `finding(_, evidence:)`, `monitorStateChanged`, `activity`,
`sessionFolderResolved`, `rosterReady`, `refreshCompleted`, `trace`.
**Add (additive, no JSON/exit impact):**

| New case | Payload | Tier |
|---|---|---|
| `playlistInformation(PlaylistInformation)` | one-time first-load summary | normal + verbose (quiet omits) |
| `playlistLifecycle(PlaylistLifecycleEvent)` | lifecycle transition | normal + verbose; recorded to timeline |

---

## 2. Presentation roles & terminal mode

### `PresentationRole` (new — enum)
Closed set decoupling meaning from color (D4, FR-009/FR-010/FR-011).

`heading · identifier · success · progress · metadata · warning · error · evidencePath · summary`

- Each role maps to a restrained 8/16 ANSI styling (FR-009a). Color is never the sole signal (FR-010):
  every role also carries a label/marker/indentation that survives plain text.

### `GlyphStyle` (new — enum)  `.unicode | .ascii`
Status-marker capability axis, independent of color (D5, FR-013).

- `.unicode` → `✓ OK` / `⚠ WARN` / `✗ ERROR` (monochrome, colored by severity).
- `.ascii` → `[OK]` / `[WARN]` / `[ERR]`.
- Derived from environment: UTF-8 in `LANG`/`LC_*` → `.unicode`; `TERM=dumb` or non-UTF-8 → `.ascii`.

### `TerminalOutputMode` (reuse + extend)
Existing: `colorEnabled: Bool`, `verbosity: Verbosity`.
**Add**: `glyphStyle: GlyphStyle`. Construction inputs gain UTF-8 capability detection alongside the
existing `isTTY / noColorEnv / noColorFlag / termIsDumb`.

### `Verbosity` (reuse) `.quiet | .normal | .verbose`
Controls human-readable tier only (FR-021); never affects findings/evidence/reports/structured output/exit.

---

## 3. Output blocks & spacing

### `OutputBlock` (new — concept, may be a renderer-internal value)
A contiguous human-readable unit (spec key entity "Output Block"): heading/context, primary outcome,
optional subordinate detail, controlled spacing.

| Field | Type | Notes |
|---|---|---|
| `kind` | `BlockKind` | see below |
| `lines` | `[StyledLine]` | rendered lines, no internal blank lines |
| `at` | `Date?` | originating occurrence (for ordering/timestamps) |

### `BlockKind` (new — enum)
`sessionSetup · roster · playlistInformation · refreshResult · lifecycleNotice · findingGroup · summary`

### Blank-line grammar (D6, FR-004/FR-005/FR-017j — **user directive**)
Invariants enforced by the block-emitting writer (testable, SC-005/SC-006):
1. Exactly **one** blank line between adjacent blocks.
2. **No** blank line within a block; a refresh result + its findings + its evidence is **one** block and is
   never interrupted by another playlist's output (FR-005).
3. No leading/trailing blank-line runs; consecutive blanks collapse to one.
4. A `playlistInformation` block is internally divided into coherent field groups separated by exactly one
   empty line (FR-017j).
5. The grammar is **disabled** for the `--json` machine stream and other non-human output (FR-028).

---

## 4. Playlist Information Block

### `PlaylistInformation` (new — value, built once at first load) (D7, FR-017a–j)
Identical content across normal terminal, verbose terminal, and Markdown report (FR-017c). Quiet terminal
omits it (FR-017a). Built once; later refreshes never revise it (FR-017d).

| Field | Type | Notes |
|---|---|---|
| `playlistID` | `String` | header (bold in styled terminal, FR-017i) |
| `kind` | `.master \| .media` | selects field set |
| `master` | `MasterInfo?` | present iff master |
| `media` | `MediaInfo?` | present iff media |

#### `MasterInfo` (FR-017e)
`id+type`, `hlsVersion`, `independentSegments`, `variantCount`, `uniqueMediaPlaylistCount`,
`renditionCountsByType` (audio/subtitles/closed-captions), `iFrameStreamCount`, `distinctResolutions`,
`distinctCodecs`, `bandwidthRange` (min–max), `frameRateRange` (min–max), `sessionProtection: Protection`.

#### `MediaInfo` (FR-017f, FR-017g)
`id+type` (media-playlist type or live/event/VOD via `StreamClassifier` + `hasEndList`), `hlsVersion`,
`segmentCount`, `totalListedDuration`, `targetDuration`, `medianSegmentDuration`,
`segmentDurationRange` (min–max), `mediaSequence`, `discontinuitySequence`, `discontinuityCount`,
`endList`, `independentSegments`, `iFramesOnly`, `segmentFormats` (one or `Mixed`), `byteRangeUsed`,
`programDateTimeAvailable`, `protection: Protection`.
**MUST NOT** copy master-derived resolution/codec/bandwidth/frame-rate/language/role (FR-017g).

- **Derivation**: every field maps to existing `PlaylistModel` data (see research D7), except `protection`
  (see §5). Segment-duration stats are computed from the **first loaded snapshot** only (FR-017d).
- **Missing values** (FR-017h): `Unknown` (unobservable) vs `Not declared` (omitted); multiple observed
  values listed distinctly or `Mixed` — never silently coerced.

---

## 5. Protection classification (minimal additive metadata) (D8, FR-017b)

### `PlaylistModel` additive surface (reuse + extend — read-only)
The parser already detects keys (`MediaPlaylist.hasEncryptionKeys`). Expose the **declared** key metadata it
tokenizes:

| Type | Add | Source tag |
|---|---|---|
| `MediaPlaylist` | `keyMethod: String?`, `keyFormat: String?` | `EXT-X-KEY` `METHOD` / `KEYFORMAT` |
| `MasterPlaylist` | `sessionKeyMethod: String?`, `sessionKeyFormat: String?` | `EXT-X-SESSION-KEY` |

Additive, read-only; **no** validation rule, finding, schema, or exit-code change (FR-002).

### `Protection` (new — enum) classified by pure `PlaylistProtection.classify`
- `none` → "None" (no key / `METHOD=NONE`)
- `encryptedAES128` → "Encrypted (AES-128)" (`METHOD=AES-128`, standard keyformat)
- `drm(keyFormat: String)` → "DRM (<key format>)" (non-AES-128 method or vendor `KEYFORMAT`, e.g.
  FairPlay/Widevine/PlayReady)

Master block summarizes session protection with the same vocabulary (FR-017b).

---

## 6. Incident timeline & lifecycle

### `IncidentTimeline` (new — value) (D9, FR-025c–h)
Ordered, deterministic list rendered once in the Markdown report.

| Field | Type | Notes |
|---|---|---|
| `entries` | `[TimelineEntry]` | sorted by `(at, sequence)` |

### `TimelineEntry` (new — value)
| Field | Type | Notes |
|---|---|---|
| `at` | `Date` | occurrence instant (same as terminal, FR-025e) |
| `sequence` | `Int` | monotonic per-session; tiebreaker for equal `at` (FR-025g/SC-008c) |
| `kind` | `TimelineKind` | see below |
| `findingAnchor` | `String?` | for `.finding` — links to the complete severity-grouped entry (FR-025f) |
| `summary` | `String` | compact text; finding entries do **not** duplicate message/evidence (SC-008b) |

### `TimelineKind` (new — enum)
`finding(severity) · operationalFailure · evidenceCaptureFailure · shutdown · lifecycle(PlaylistLifecycleEvent.Kind)`

- **Excludes** routine successful refreshes (FR-025d/SC-008a).
- Finding entries appear **once** in severity-grouped sections; the timeline only references them
  (FR-025f, SC-008b).

### `PlaylistLifecycleEvent` (new — value) (D10, FR-025c, key entity)
| Field | Type | Notes |
|---|---|---|
| `playlistID` | `String` | |
| `at` | `Date` | occurrence (D1) |
| `kind` | `Kind` | `.unavailable \| .recovered \| .added \| .removed \| .identityChanged` |

- `unavailable`/`recovered` derive from `monitorStateChanged`/staleness; `added`/`removed`/
  `identityChanged` from roster diffs across refreshes.

### Session recording state (reuse + extend `ValidationSession`)
- `timelineSequence: Int` — monotonic counter, increments per recorded timeline event (FR-025g).
- `loadedPlaylistInfo: Set<String>` — ensures each `PlaylistInformation` is emitted once (FR-017a/d).
- `previousRoster` — for lifecycle diffing.
- All occurrence timestamps read from the existing injected `now` clock (deterministic in tests).

---

## 7. Reuse — unchanged frozen types (FR-002/FR-028)

`Finding` (incl. `observedAt`, `jsonEncoder`, `prettyJSONEncoder`), `EvidenceReference`/`EvidenceResolver`,
`SnapshotID`, `AliasRegistry`/`PlaylistAlias` (ID grammar), report JSON **schema v1**, `FindingsLog` JSONL,
`--json` status stream, `SelectionPromptPolicy`, exit codes 0/1/2/3/130. Feature 004 adds presentation and
timeline/info models around these without altering their data or formatting.

---

## Entity → requirement map

| Entity | Requirements |
|---|---|
| `TimestampedEvent`, timestamp formatters | FR-008a/b/c, FR-025a/b, SC-003a/b/c |
| `PresentationRole`, whole-line tint | FR-009/009a, FR-010, FR-011/011a |
| `GlyphStyle`, markers | FR-013, SC-005 |
| `OutputBlock`/`BlockKind`, blank-line grammar | FR-003/004/005/017j, SC-005/006 (**user directive**) |
| `PlaylistInformation`/`MasterInfo`/`MediaInfo` | FR-017a–j, SC-012/013 |
| `Protection`, model key metadata | FR-017b, SC-013 |
| `IncidentTimeline`/`TimelineEntry` | FR-025c–h, SC-008a/b/c |
| `PlaylistLifecycleEvent` | FR-025c |
| Reuse (frozen) | FR-002, FR-028, SC-011 |

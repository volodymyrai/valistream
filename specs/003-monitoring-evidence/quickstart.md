# Quickstart & Validation: Reliable Monitoring and Evidence

Runnable validation for each user story. Proves the feature end-to-end without changing any frozen
behavior. Details live in [data-model.md](data-model.md) and [contracts/](contracts/) — not repeated
here.

## Prerequisites

- macOS 14+, Xcode toolchain; Swift 6.x (`swift-tools-version: 6.3`).
- MCPs available (CLAUDE.md hard requirement): **serena**, **xcode-tools**. **No WebSearch.**
- Build/test through **xcode-tools** (`BuildProject`, `RunSomeTests`/`RunAllTests`) or `swift test`
  piped through **xcsift**. Unit/conformance: package (`swift test`). Integration: Xcode `Valistream`
  scheme / `Valistream.xctestplan`, scripted in-process transport stubs (no HTTP server).
- Build/test commands and seams: see `mem:implementation-setup` / `mem:implementation-progress`.

## Build & test (smoke)

```bash
# unit + conformance (package) — pipe through xcsift
swift test            # via xcsift skill

# full suite incl. integration — Xcode Valistream scheme (xcode-tools RunAllTests)
```

Expected: green; the FROZEN guards (`ReportJSONSchemaTests`, `RuleEngineTests`, conformance corpus,
exit-code assertions) still pass — proving zero regression (SC-009).

---

## US1 — Evidence (P1, MVP)

**Scenario**: run against a scripted stream producing ≥ 1 ERROR, ≥ 1 WARN, and ≥ 1 continuity finding.

**Checks**
- Each ERROR/WARN in the terminal names an evidence file `playlists/<id>/<id>_<n>.m3u8` that **exists**
  on disk and contains the relevant content (FR-004; SC-001).
- The continuity finding names **exactly two** consecutive snapshots `<id>_<n-1>` and `<id>_<n>`
  (FR-006; SC-001).
- The Markdown report shows the same reference(s) as **inline code spans** (relative path only, not a
  link) (FR-005).
- A finding whose body could not be archived prints `no body captured for <id>` — **no raw URL, no
  dangling path** (FR-009).
- From the **structured** report, the evidence file(s) are recoverable via `resource` (URL) +
  `refreshIndex` against the artifact index, with **no schema change** (FR-008; SC-009).

**Automated**: unit `EvidenceResolverTests` (single / continuity-pair / unavailable-by-ID / missing-one
edge); integration evidence-in-output test asserting the printed path exists and matches the archive.

---

## US2 — Clutter-free, steady heartbeat (P2)

**Scenario A (roster + zero URLs)**: run with very long playlist URLs.
- A start-of-session roster prints each ID → full URL + role **before** fetching (FR-011).
- After the roster, **no** full URL appears in the terminal body — at normal **and** `--verbose`
  (FR-012; SC-003).

**Scenario B (monotonic heartbeat)**: live session via the deterministic harness (ManualClock); inject
≥ 20 stray Enter presses through the input seam.
- Displayed refresh count is **monotonic non-decreasing** and equals refreshes performed — zero
  backward jumps, zero miscounts (FR-013/014; SC-004).
- The status region is never corrupted by stray input (echo suppressed via `LiveInputGuard`).

**Scenario C (verbose distinctness)**: same run at normal vs `--verbose`.
- `--verbose` adds ≥ 5 categories absent at normal (fetch intent, fetch result, per-playlist/per-rule
  validation, archive writes, refresh cadence, continuity compares) — clearly not a near-copy (FR-015;
  SC-005). All verbose lines are ID-based.

**Automated**: unit monotonic-counter test + `TraceFormatter` wording tests; integration roster/zero-URL
scan, heartbeat-monotonicity-under-stray-input (seam), verbose-vs-normal line-set difference.

---

## US3 — Meaningful IDs (P3)

**Scenario**: run against a master advertising several video renditions differing by resolution and
codec, plus audio/subtitle/I-frame.

**Checks**
- master ID is exactly `master` (FR-017; SC-007).
- each video ID is `<height>p_<codecs>` and renditions differing only by codec (or only by resolution)
  get **distinct** IDs (FR-018; SC-006/007): e.g. `1080p_avc1`, `1080p_avc1-mp4a`, `720p_avc1`.
- audio/subtitle/I-frame get clear role IDs: `audio_en`, `audio_en_commentary` (same-lang collision),
  `subs_en`, `iframe_720p`.
- two would-be-identical IDs are de-duplicated deterministically; attribute-less playlists get the
  documented role+ordinal fallback (FR-019/020).
- re-run the same stream → identical IDs; within a run each playlist keeps its ID across refreshes
  (SC-006).

**Automated**: unit `AliasRegistry`/ID-scheme tests (height+`p`, codec fourCC trim + `-` join, slug,
multi-codec, collision suffix, fallback, filesystem-safe charset); `SnapshotID` formatting tests.

---

## US4 — Process-all-by-default (P4)

**Scenario matrix**

| Invocation | Expected |
|------------|----------|
| *(no flags)*, even on a TTY | all renditions processed, **no prompt** (FR-021; SC-010) |
| `--all` | rejected as unknown option → **exit 2** (FR-022; SC-010) |
| `--preselect <pattern>` | matching subset processed, **no prompt** (FR-023) |
| `--select` on a TTY | interactive checklist, **all pre-selected** (FR-024) |
| `--select` + `--preselect` | usage error → **exit 2** (FR-025) |
| `--select` on non-TTY | falls back to all + prints notice (FR-025) |

**Automated**: unit `SelectionPromptPolicyTests` (prompt-iff `--select`+TTY; mutual exclusion; non-TTY
fallback); integration selection-matrix (prompt closure not called for default/`--preselect`; pattern
filter applied; `--all` exits 2).

---

## US5 — Pretty JSON files (P5)

**Scenario**: run a session; open the structured report and a `*.meta.json` sidecar; capture `--json`.

**Checks**
- every JSON **file** on disk is multi-line/indented with stable key ordering (FR-026; SC-008).
- the structured report parses to the **same logical content** as before and still validates against the
  frozen schema (FR-027; SC-008/009).
- the `--json` status stream remains **exactly one compact object per line** (FR-028; SC-008).

**Automated**: unit pretty-vs-compact encoder tests (report + sidecar multi-line & schema-valid; stream
encoder stays compact/single-line).

---

## Manual (cannot run headless)

- Real-stream run: confirm roster, ID-based heartbeat, evidence paths openable in < 15 s (SC-002),
  and `--select` interactive checklist on a real terminal.
- 30-minute live session with ≥ 20 real Enter presses to confirm SC-004 on a real TTY.

## Definition of done (per story)

A story is done when its automated checks above are green, the FROZEN guards still pass (SC-009), and
its acceptance scenarios in [spec.md](spec.md) hold. Tests are written **first** (Constitution II).

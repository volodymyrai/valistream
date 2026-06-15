# Phase 0 Research: Readable Output and Onboarding (004)

**Feature**: 004-output-readability | **Date**: 2026-06-15 | **Spec**: [spec.md](./spec.md)

This document resolves every open question needed to plan feature 004. It is grounded in the
**existing** codebase (features 001/002/003), which already ships a color/verbosity output layer.
The feature therefore **refines and extends** that layer rather than building output from scratch.

## Existing infrastructure (baseline — confirmed by inspection)

| Concern | Where it lives today | Status for 004 |
|---|---|---|
| Color gating | `ValistreamCore/.../Output/TerminalOutputMode.swift` (`colorEnabled = isTTY && !NO_COLOR && !--no-color && TERM != "dumb"`, carries `verbosity`) | **Reuse**, extend with glyph capability |
| Styling (Rainbow) | `Valistream/Valistream/TerminalWriter.swift` (`formatFinding`, `writeStatus`, `writeBlankLine`, `styledLine`) | **Extend** (whole-line tint, markers, grouping) |
| Progress / heartbeat | `Output/ProgressFormatter.swift` + CLI `ProgressView.swift` (`\r\u{1B}[K` transient line) | **Reuse**, keep non-competing |
| Verbose trace | `Output/TraceFormatter.swift` + `SessionEvent.trace` | **Reuse** |
| Event stream | `Session/SessionConfig.swift` → `SessionEvent` enum, `ActivityProgress`, `RosterEntry` | **Extend** (timestamps, info, lifecycle) |
| Findings | `Validation/Finding.swift` — already has `observedAt: Date`, `resource`, `refreshIndex`, `severity`, `category` | **Reuse** `observedAt` |
| Report builder | `Session/SessionReportBuilder.swift` (`buildJSON` frozen schema v1, `buildMarkdown`: header/Summary/Legend/Findings/Per-playlist) | **Extend** (timeline, info blocks, timestamps, callouts) |
| Playlist model | `Playlist/PlaylistModel.swift` (`MasterPlaylist`, `MediaPlaylist`, `VariantStream`, `IFrameStream`, `Rendition`, `SegmentRef`, `ByteRange`, `Resolution`) | **Reuse**; add protection metadata only |
| Dependencies | swift-argument-parser, Rainbow, Promptberry (CLI); Core = Foundation-only | **No new dependency** |
| Version | `MARKETING_VERSION` + `CommandConfiguration.version` = `0.3.0` | Bump to `0.4.0` |
| Coverage source | `Valistream/TestPlans/Valistream.xctestplan` — `codeCoverage` now enabled for `Valistream` + `ValistreamCore` | **New input** for badge/SC-010 |

---

## Decisions

### D1 — Event-occurrence timestamps threaded through every message

- **Decision**: Stamp every emitted `SessionEvent` with the wall-clock instant **at which the underlying
  event occurred**, captured inside `ValidationSession` at emission time, not at render time. `Finding`
  already carries `observedAt: Date`; reuse it for finding events. For non-finding events, add an
  occurrence `Date` to the event (an associated `at: Date` on each case, or a wrapping
  `TimestampedEvent { let at: Date; let event: SessionEvent }` envelope yielded by the session stream).
  Preferred: a wrapping envelope so the existing case shapes stay stable and machine consumers are
  untouched.
- **Rationale**: FR-008c / FR-025e / SC-003c require the timestamp to represent occurrence and to be
  identical across terminal and report. Capturing once at emission and carrying the value forward is the
  only way reordering/buffering cannot change it. The session is the single place that observes the
  event, so it owns the clock read.
- **Clock source**: the session already takes an injectable `now: () -> Date` (used by monitoring/
  staleness). Reuse it so tests pin time deterministically (ManualClock).
- **Alternatives rejected**: stamping in the renderer (violates FR-008c — render time ≠ event time);
  a global mutable clock (untestable, race-prone under strict concurrency).

### D2 — Two pure timestamp formatters

- **Decision**: Add pure formatters in `Output/`:
  - `TerminalTimestampFormatter` → `[HH:mm:ss.SSS]`, 24-hour, **local** timezone, milliseconds (FR-008b).
  - `ReportTimestampFormatter` → full ISO 8601 with date, 24-hour time, milliseconds, numeric UTC
    **offset**, local timezone (FR-025b), e.g. `2026-06-15T14:03:07.412+02:00`.
- **Rationale**: deterministic, allocation-light formatting reused by terminal and report keeps the two
  surfaces correlatable to the millisecond (SC-003b). Foundation `Date.FormatStyle` /
  `ISO8601FormatStyle` cover both; fixed format strings avoid locale drift.
- **Alternatives rejected**: ad-hoc string building per call site (inconsistent, FR-006 risk); UTC-only
  (spec mandates local time for both surfaces).

### D3 — One persistent result per successful refresh (FR-008, SC-002)

- **Decision**: Normal mode emits exactly **one** persistent result line per completed refresh, driven by
  the existing `refreshCompleted` event. Remove duplicate request/comparison/storage/validation/"success"
  emissions from the normal tier (they remain available as verbose `trace` lines). The heartbeat is
  excluded from the count.
- **Rationale**: SC-002 caps a warning-free refresh at one persistent line (excluding heartbeat); FR-018
  pushes request/rule/comparison/archive/scheduling detail into verbose unless they raise a finding.
- **Alternatives rejected**: keep per-stage lines but visually dim them (still multiple lines, fails
  SC-002).

### D4 — Presentation roles + whole-line severity tint (FR-009, FR-011a)

- **Decision**: Define a closed set of **presentation roles** (heading, identifier, success, progress,
  metadata, warning, error, evidencePath, summary) mapped to the restrained 8/16 ANSI palette (FR-009a:
  error=red, warning=yellow, success=green, identifier/path=cyan, metadata=dim gray, heading=bold).
  Result and finding lines are tinted **whole-line** by severity; structural context lines keep
  token-scoped styling. Implemented in `TerminalWriter` via a `styledLine(role:)` / `tintedLine(severity:)`
  split.
- **Rationale**: FR-011a wants severity scannable at a glance via line tint while headings/identifiers/
  paths stay token-scoped; FR-010 forbids color as the only signal (label + marker carry meaning when
  color is off).
- **Alternatives rejected**: token-only styling everywhere (severity not scannable, fails FR-011a);
  256-color/truecolor palette (FR-009a forbids).

### D5 — Status markers: monochrome Unicode with ASCII fallback (FR-013)

- **Decision**: Render restrained monochrome Unicode text symbols colored by severity, each paired with a
  readable label (e.g. `✓ OK`, `⚠ WARN`, `✗ ERROR`), falling back to ASCII `[OK]` / `[WARN]` / `[ERR]`
  when Unicode cannot be relied on. Add a `glyphStyle` (`.unicode` / `.ascii`) to `TerminalOutputMode`,
  derived from environment (UTF-8 in `LANG`/`LC_*` → unicode; `TERM=dumb` or non-UTF-8 → ascii). No
  colorful/emoji glyphs in the terminal.
- **Rationale**: FR-013 bans variable-width emoji in the terminal (alignment/compat) and mandates the
  ASCII fallback. Unicode capability is independent of color, so it is a separate axis from `colorEnabled`.
- **Alternatives rejected**: emoji markers (FR-013 forbids); tying glyphs to `colorEnabled` (a no-color
  UTF-8 terminal should still get aligned Unicode markers).

### D6 — Blank-line grammar between logical groups (FR-004, FR-017j, **user directive**)

- **Decision**: Treat human-readable terminal output as a sequence of **blocks** (groups). Exactly **one**
  blank line separates adjacent blocks; **no** blank line is inserted between lines **within** a block or
  after every message. Define the block taxonomy and a small block-emitting helper (a buffering writer)
  that guarantees the grammar: collapses consecutive blanks to one, suppresses leading/trailing blank
  runs, and is **disabled for the `--json` machine stream** (FR-028). Playlist-information blocks are
  internally divided into coherent field groups separated by exactly one empty line (FR-017j).
- **Block taxonomy**: session-setup block; playlist roster block; one playlist-information block (per
  playlist, first load); one refresh-result block (result line + its findings + its evidence — kept
  contiguous, FR-005); a lifecycle notice; the final summary block. In quiet mode, each per-playlist/
  snapshot finding group is a block.
- **Rationale**: directly satisfies FR-004 ("blank lines at meaningful boundaries without a blank line
  after every message"), FR-005 (contiguity), FR-017j, and the user's explicit instruction to *require*
  empty lines between logical groups in stdout. A grammar (not ad-hoc `print("")`) makes it testable
  (SC-005/SC-006) and keeps the machine stream clean.
- **Alternatives rejected**: a blank line after every message (noisy, violates FR-004); leaving spacing to
  individual call sites (drift, untestable).

### D7 — Playlist Information Block (FR-017a–j, SC-012/SC-013)

- **Decision**: Add a pure `PlaylistInformation` value computed **once** when a playlist is first loaded,
  carried by a new additive `SessionEvent.playlistInformation(...)` emitted once per playlist. Render it
  in normal + verbose terminal and in the Markdown report with identical fields/values (FR-017c);
  **omit in quiet** terminal output (FR-017a). Media-block segment-duration stats (median, min–max) are
  computed from the playlist's **first loaded snapshot** and never revised (FR-017d). A media block shows
  only facts that media playlist declares (FR-017g); master-derived resolution/codec/bandwidth/frame-rate/
  language/role stay in the master block.
- **Field sources** (all available in `PlaylistModel` except protection — see D8):
  - **Master (FR-017e)**: id+type; `version`; `hasIndependentSegments`; `variants.count`; unique referenced
    media-playlist count (distinct variant URIs); rendition counts by `Rendition.type`; `iFrameStreams.count`;
    distinct `VariantStream.resolution`; distinct `VariantStream.codecs`; bandwidth range
    (`min/max bandwidth`); frame-rate range (`min/max frameRate`); session-protection summary (D8).
  - **Media (FR-017f)**: id + `playlistType`/live-event-VOD (via existing `StreamClassifier` + `hasEndList`);
    `version`; `segments.count`; total listed duration (Σ `SegmentRef.duration`); `targetDuration`; median +
    min–max segment durations; `mediaSequence`; `discontinuitySequence`; discontinuity count
    (Σ `hasDiscontinuity`); `hasEndList`; `hasIndependentSegments`; `isIFramesOnly`; observed segment
    format(s) (from segment URI extension; `Mixed` when >1, FR-017h); byte-range usage (any `byteRange != nil`);
    program-date-time availability (any `programDateTime != nil`); protection classification (D8).
- **Missing values** (FR-017h): render `Unknown` (unobservable) vs `Not declared` (omitted declaration);
  list multiple observed values distinctly or label `Mixed` — never silently pick one.
- **Rationale**: the model already carries the structural facts, so the block is mostly presentation; one
  event + one pure builder + two renderers (terminal, markdown) keeps it DRY and identical across surfaces.
- **Alternatives rejected**: building the summary separately in CLI and report (drift risk, fails
  FR-017c/SC-012); recomputing stats each refresh (fails FR-017d).

### D8 — Protection classification (FR-017b) — minimal additive metadata

- **Decision**: Surface declared key metadata that the parser already tokenizes but currently collapses to
  `MediaPlaylist.hasEncryptionKeys: Bool`. Add additive read-only fields exposing the declared
  `EXT-X-KEY` `METHOD` + `KEYFORMAT` (media) and `EXT-X-SESSION-KEY` (master), then a pure
  `PlaylistProtection.classify(...)` returning `None` / `Encrypted (AES-128)` / `DRM (<key format>)`.
  Media blocks classify per playlist (FR-017b); the master block summarizes session protection with the
  same vocabulary.
- **Rationale**: classification needs the KEY `METHOD`/`KEYFORMAT`, not just a bool. The change is purely
  additive metadata read from already-parsed tags — it adds **no** validation rule and does not alter any
  finding, schema, or exit code (FR-002 respected). Justified under YAGNI because FR-017b/e/f require it
  directly.
- **Alternatives rejected**: keep the bool and guess `AES-128` (wrong for SAMPLE-AES/DRM, fails FR-017b);
  re-tokenize raw text in the presentation layer (duplicates the parser).

### D9 — Incident timeline in the Markdown report (FR-025c–h, SC-008a/b/c)

- **Decision**: Add a pure `IncidentTimeline` model: an ordered list of timestamped entries for every
  warning, error, operational failure, evidence-capture failure, shutdown/interruption, and playlist
  lifecycle change. Routine successful refreshes are excluded (FR-025d). Finding entries are **compact**
  and **link** to the complete finding in its severity-grouped section (anchor link); no finding message/
  evidence is duplicated in the timeline (FR-025f/SC-008b). Ordering is by occurrence timestamp; ties keep
  recorded sequence via a monotonic per-session sequence counter (FR-025g/SC-008c). The timeline is built
  from the same recorded occurrence instants used by the terminal (FR-025e).
- **Rationale**: a single ordered model rendered once gives deterministic, navigable, non-duplicated output
  and survives repeated generation (SC-008c).
- **Alternatives rejected**: interleaving the timeline into per-playlist sections (not chronological, fails
  SC-008a); duplicating finding detail in the timeline (fails SC-008b).

### D10 — Playlist lifecycle events (FR-025c, key entity)

- **Decision**: Model `PlaylistLifecycleEvent` with cases `unavailable`, `recovered`, `added`, `removed`,
  `identityChanged`. `unavailable`/`recovered` derive from the existing `monitorStateChanged`/staleness
  signals; `added`/`removed`/`identityChanged` derive from roster diffs across refreshes. Each event is
  timestamped at occurrence (D1), recorded into the incident timeline (D9), and surfaced as a normal-mode
  lifecycle notice (FR-017).
- **Rationale**: these five transitions are named explicitly by the spec (key entity + FR-025c). Centralizing
  them as one event type keeps terminal and report in sync.
- **Alternatives rejected**: inferring lifecycle from log scraping at report time (loses occurrence instant,
  fails FR-025e).

### D11 — Markdown enrichment with graceful degradation (FR-025/026/027/027a)

- **Decision**: Outcome-first summary; stable linked section order (Summary → Incident Timeline →
  Findings (errors before warnings before info) → Playlist Information → Legend → Session details).
  Severity uses GitHub alert/callout blocks (`> [!WARNING]`, `> [!CAUTION]`) and emoji severity icons
  **in the report**; every styled element degrades to readable plain text (callout → blockquote, icon
  beside its text label). No shields-style badges and no nonstandard HTML in the **report** (FR-027a) —
  badges live only in the README (FR-029a). No terminal styling/cursor bytes in the report (FR-027).
- **Rationale**: matches the clarified report richness decision; emoji are acceptable in Markdown (unlike
  the terminal, FR-013) because GitHub renders them and plain-text fallback is preserved.
- **Alternatives rejected**: HTML/badges in the report (FR-027a forbids); terminal ANSI in the report
  (FR-027 forbids).

### D12 — README rewrite, badges, and coverage source (FR-029–037, FR-029a, SC-009/SC-010)

- **Decision**: Rewrite `README.md` to the full GitHub structure (FR-029): name + description, motivation,
  capabilities, how it works, quick start, installation, usage, option reference, output modes, generated
  artifacts, realistic examples, exit codes, troubleshooting, limitations/platform support, resources.
  - **Badges (FR-029a)**: license, latest release/version (`0.4.0`), platform/Swift, and **code coverage**.
    Coverage value is taken from the now-enabled `Valistream.xctestplan` coverage run (D15); a badge whose
    fact cannot be verified is omitted, never shown stale.
  - **Install (FR-030)**: primary = download prebuilt `valistream-cli.zip` from GitHub Releases and run;
    secondary = verified source build; unpublished channels (Homebrew, etc.) marked unsupported.
  - **Quick start (FR-031/037)**: a stable, credential-free public HLS test stream that runs as-is on
    paste, confirmed to resolve and run cleanly with `0.4.0` before inclusion.
  - **Examples (FR-033/034)**: plain-text fenced excerpts only (no screenshots/GIFs/casts); sanitized,
    stable inputs; quiet/normal/verbose/no-color/structured/Markdown/session-dir excerpts.
- **Rationale**: encodes every README-related clarification; keeps documentation verifiable against the
  released binary (SC-010).
- **Alternatives rejected**: binary/animated media (FR-033 forbids — GitHub shows no ANSI in code blocks);
  documenting unverified install channels (FR-030 forbids).

### D13 — Version 0.4.0 (FR-001)

- **Decision**: Bump `MARKETING_VERSION` (all configs in `Valistream.xcodeproj/project.pbxproj`) and
  `CommandConfiguration.version` from `0.3.0` → `0.4.0`; verify all user-facing version references agree
  (README, `--version`, help discussion).
- **Rationale**: FR-001 + Assumption that the version is already being treated as `0.4.0`.

### D14 — Compatibility freeze verification (FR-002, FR-028, SC-011)

- **Decision**: Add/extend guard tests proving zero change to: validation results, rule/finding IDs,
  structured JSON report **data** and schema, JSON Lines (`FindingsLog`) behavior, the `--json` status
  stream format, selection behavior, and exit codes 0/1/2/3/130. Human-readable changes must not leak into
  machine streams (the blank-line grammar and styling are gated off for `--json`/non-TTY).
- **Rationale**: FR-002/028 freeze the machine surfaces; SC-011 demands automated proof. The 003 guard
  tests (`ReportJSONSchemaTests`, RuleEngine/conformance, exit-code checks) are the anchor.
- **Alternatives rejected**: manual diffing (not repeatable, fails SC-011).

### D15 — Coverage measurement mechanics (**user directive**)

- **Decision**: Coverage is measured from `Valistream/TestPlans/Valistream.xctestplan` (now `codeCoverage`
  enabled for both `Valistream` and `ValistreamCore`). Produce the percentage by running the `Valistream`
  scheme tests with a result bundle and reading line coverage via `xcrun xccov view --report --json
  <Result.xcresult>`. The README coverage badge reflects that current measured value at release; if no
  continuously published source exists yet, the badge is generated from this release-time measurement and
  re-verified before completion (FR-029a, SC-010). This is the single source of coverage truth for the
  badge.
- **Rationale**: directly uses the coverage the user enabled; keeps the badge verifiable (no broken/stale).
- **Alternatives rejected**: a hard-coded coverage badge (stale, FR-029a forbids); standing up CI in this
  feature (out of scope; the xctestplan source suffices for a verifiable value).

---

## Resolved unknowns

All Technical Context items are decided; **no `NEEDS CLARIFICATION` remains**. The 19 spec clarifications
(Session 2026-06-15) plus D1–D15 cover timestamps, palette, markers, grouping/blank-lines, the playlist
information block, protection, the incident timeline, lifecycle events, report enrichment, README/badges,
coverage source, versioning, and compatibility.

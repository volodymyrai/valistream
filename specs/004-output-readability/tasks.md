---
description: "Dependency-ordered, test-first task list for feature 004 (Readable Output and Onboarding)"
---

# Tasks: Readable Output and Onboarding (004)

**Input**: Design documents from `specs/004-output-readability/`
**Prerequisites**: plan.md, spec.md, research.md (D1–D15), data-model.md, contracts/ (terminal-output,
report-format, compatibility, readme)

**Tests**: Constitution Principle II (Test-First, NON-NEGOTIABLE) is in force; no test waiver is recorded.
Every behavior change ships its tests **first** (Red → Green → Refactor). Compatibility guard tests are
written early as a regression net for the frozen machine surfaces (FR-002/FR-028, SC-011).

**Organization**: Tasks are grouped by user story (P1–P4) for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description with file path`

- **[P]**: parallelizable — different file, no dependency on an incomplete task
- **[Story]**: `[US1]`–`[US4]` for user-story phases only (Setup/Foundational/Polish carry no story label)
- File paths are **repo-root filesystem paths** (plan.md → "Target → source-folder paths"). The CLI tool
  lives at the tripled `Valistream/Valistream/Valistream/`; integration tests at
  `Valistream/Valistream/ValistreamIntegrationTests/`. **Never** use the shorter Xcode navigator path.

## Path conventions (this feature)

| Area | Path |
|---|---|
| Core production | `Valistream/ValistreamCore/Sources/ValistreamCore/` |
| Core unit tests | `Valistream/ValistreamCore/Tests/ValistreamCoreTests/` |
| CLI tool | `Valistream/Valistream/Valistream/` |
| Integration tests | `Valistream/Valistream/ValistreamIntegrationTests/` |
| Test plan (coverage) | `Valistream/TestPlans/Valistream.xctestplan` |
| Project file (version) | `Valistream/Valistream/Valistream.xcodeproj/project.pbxproj` |
| README | `README.md` (repo root) |

> Tooling (binding): build via xcode-tools `BuildProject`; unit via `swift test` in
> `Valistream/ValistreamCore/`; integration + coverage via the `Valistream` scheme /
> `Valistream.xctestplan` (`RunAllTests`/`RunSomeTests`); pipe `xcodebuild`/`swift test` through `xcsift`.
> Use **serena** for code inspection/editing; **xcode-tools** for build/validate/docs.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: confirm a green starting point and a verifiable coverage source before any change lands.

- [X] T001 Establish the frozen-surface baseline: `BuildProject` (workspace) green, then run the 003 guard
      suite (`ReportJSONSchemaTests`, RuleEngine/conformance, exit-code checks) via xcode-tools
      `RunSomeTests` against `Valistream/TestPlans/Valistream.xctestplan`; record the all-green baseline
      (anchor for compatibility V1, SC-011).
- [X] T002 [P] Confirm `codeCoverage` is enabled for `Valistream` + `ValistreamCore` in
      `Valistream/TestPlans/Valistream.xctestplan` (kept for local diagnostics only; the README coverage
      badge is dropped per FR-029a — no verifiable durable source, so no badge value is captured).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the shared, Foundation-only Core backbone every rendering story sits on — occurrence-stamped
events, the two timestamp formatters, the playlist information/protection model, the lifecycle event, and
the session recording/emission plumbing. Plus the compatibility regression net.

**⚠️ CRITICAL**: No user-story rendering work (US1–US3) can begin until this phase is complete. The
`--json` machine stream and all frozen surfaces MUST stay byte-identical (verified by T008).

### Tests for Foundational (write first; must FAIL before impl) ⚠️

- [X] T003 [P] `TimestampFormatterTests` in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Output/TimestampFormatterTests.swift`
      — terminal `[HH:mm:ss.SSS]` 24h local and report ISO-8601 local with milliseconds + numeric UTC
      offset; same instant correlates within 1 ms; render delay/reorder never re-stamps (T1–T4, R5/R6,
      SC-003b/c).
- [X] T004 [P] `PlaylistProtectionTests` in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Playlist/PlaylistProtectionTests.swift`
      — classify `None` / `Encrypted (AES-128)` / `DRM (<key format>)` from declared key method/keyformat
      (FR-017b, SC-013).
- [X] T005 [P] `PlaylistInformationTests` in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Playlist/PlaylistInformationTests.swift`
      — master fields (FR-017e), media fields (FR-017f) with no master-derived values (FR-017g),
      first-snapshot median + min–max segment durations (FR-017d), missing-value `Unknown` vs
      `Not declared` and `Mixed` (FR-017h).
- [X] T006 [P] `PlaylistInfoFormatterTests` in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Output/PlaylistInfoFormatterTests.swift`
      — surface-neutral ordered field groups are identical content for terminal and report (FR-017c,
      SC-012) and grouped coherently (FR-017j).
- [X] T007 [P] `PlaylistLifecycleEventTests` in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/PlaylistLifecycleEventTests.swift`
      — `unavailable`/`recovered`/`added`/`removed`/`identityChanged` carry playlist ID + occurrence
      instant (FR-025c, research D10).
- [X] T008 [P] `CompatibilityFreezeTests` (NEW) in `Valistream/Valistream/ValistreamIntegrationTests/CompatibilityFreezeTests.swift`
      — for a scripted session, `--json` stream, `FindingsLog` JSONL, JSON report schema v1, and
      `.meta.json` are structurally identical before/after 004 with no timestamps/blank-line grammar/ANSI
      in any machine surface; reuse 003 guards (C1–C10, V1/V2, SC-011).

### Implementation for Foundational

- [X] T009 Add the `TimestampedEvent { at: Date; event: SessionEvent }` envelope and additive
      `SessionEvent` cases `.playlistInformation(PlaylistInformation)` and
      `.playlistLifecycle(PlaylistLifecycleEvent)` in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/SessionConfig.swift`;
      keep all existing case shapes unchanged (research D1, data-model §1).
- [X] T010 [P] Create `Valistream/ValistreamCore/Sources/ValistreamCore/Output/TimestampFormatter.swift`
      — pure terminal `[HH:mm:ss.SSS]` and report ISO-8601(+offset) formatters (research D2).
- [X] T011 [P] Extend `Valistream/ValistreamCore/Sources/ValistreamCore/Playlist/PlaylistModel.swift`
      — additive read-only `keyMethod`/`keyFormat` on `MediaPlaylist` and
      `sessionKeyMethod`/`sessionKeyFormat` on `MasterPlaylist` (no rule/schema/exit change; data-model §5,
      research D8).
- [X] T012 Populate the additive key metadata from already-tokenized `EXT-X-KEY` / `EXT-X-SESSION-KEY`
      `METHOD`+`KEYFORMAT` in `Valistream/ValistreamCore/Sources/ValistreamCore/Playlist/PlaylistBuilder.swift`
      (depends T011).
- [X] T013 [P] Create `Valistream/ValistreamCore/Sources/ValistreamCore/Playlist/PlaylistProtection.swift`
      — pure `classify(...)` → `Protection` enum (`none`/`encryptedAES128`/`drm(keyFormat:)`) (depends T011,
      research D8).
- [X] T014 Create `Valistream/ValistreamCore/Sources/ValistreamCore/Playlist/PlaylistInformation.swift`
      — `PlaylistInformation` + `MasterInfo`/`MediaInfo` value types and the pure builder from
      `PlaylistModel` + first loaded snapshot (depends T011–T013, research D7).
- [X] T015 Create `Valistream/ValistreamCore/Sources/ValistreamCore/Output/PlaylistInfoFormatter.swift`
      — surface-neutral ordered label/value field groups (single content source guaranteeing FR-017c
      parity; terminal/markdown styling added by US1/US2) (depends T014).
- [X] T016 [P] Create `Valistream/ValistreamCore/Sources/ValistreamCore/Session/PlaylistLifecycleEvent.swift`
      — value + `Kind` enum (research D10).
- [X] T017 Extend `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift`
      — stamp every emitted event with its occurrence `Date` from the injected `now` clock; add
      `timelineSequence` counter, `loadedPlaylistInfo: Set<String>`, and `previousRoster` recording state
      (depends T009, research D1).
- [X] T018 Extend `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift`
      — emit `PlaylistLifecycleEvent`: `unavailable`/`recovered` from monitor/staleness signals,
      `added`/`removed`/`identityChanged` from roster diffs across refreshes (depends T016, T017).
- [X] T019 Extend `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Reporting.swift`
      — emit `playlistInformation` exactly once per playlist at first load (guarded by `loadedPlaylistInfo`,
      FR-017a/d); record timeline-eligible events (findings, failures, lifecycle, shutdown) with monotonic
      `sequence` (depends T014, T017, FR-025c–h).
- [X] T020 Confirm the machine-stream gate: the `--json`/non-human path serializes only the raw frozen
      events (no envelope timestamp, no additive human-only cases) in
      `Valistream/ValistreamCore/Sources/ValistreamCore/Session/SessionConfig.swift` and the emission path
      — makes T008 pass (C7/C10; depends T009, T017).

**Checkpoint**: Core backbone ready and machine surfaces proven unchanged — US1/US2/US3 can begin.

---

## Phase 3: User Story 1 - Follow a Live Session at a Glance (Priority: P1) 🎯 MVP

**Goal**: a normal-mode operator can identify the current phase, the latest playlist result, the first
warning, its evidence path, and the final outcome at a glance — readable terminal layer (timestamps,
blank-line grouping, whole-line tint + roles + markers, one persistent result per refresh, one-time
playlist information block, lifecycle notices, prominent final summary), with a plain-text baseline.

**Independent Test**: run a scripted normal session with several playlists, successful refreshes, and one
warning; verify named groups separated by exactly one blank line, one timestamped persistent result per
refresh, a contiguous warning block, one info block per playlist, and a prominent final summary — without
verbose mode. Re-run with `NO_COLOR`/`--no-color`/`TERM=dumb`/redirect for zero styling bytes.

### Tests for User Story 1 (write first; must FAIL before impl) ⚠️

- [ ] T021 [P] [US1] `PresentationRoleTests` in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Output/PresentationRoleTests.swift`
      — each role maps to the restrained 8/16 ANSI palette; color is never the sole signal (T14/T16,
      FR-009/009a/010).
- [ ] T022 [P] [US1] `TerminalOutputModeGlyphTests` in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Output/TerminalOutputModeTests.swift`
      — `GlyphStyle` UTF-8 detection: `.unicode` for UTF-8 `LANG`/`LC_*`, `.ascii` for `TERM=dumb`/non-UTF-8
      (T18/T19, research D5).
- [ ] T023 [P] [US1] `BlankLineGroupingTests` (NEW) in `Valistream/Valistream/ValistreamIntegrationTests/BlankLineGroupingTests.swift`
      — exactly one blank line between blocks, none within; consecutive blanks collapse; no leading/trailing
      run; a refresh result+findings+evidence stays one contiguous block; info-block field groups separated
      by one blank (T8–T13, FR-004/005/017j).
- [ ] T024 [P] [US1] `TimestampedOutputTests` (NEW) in `Valistream/Valistream/ValistreamIntegrationTests/TimestampedOutputTests.swift`
      — every human-readable terminal line carries `[HH:mm:ss.SSS]`; the value is the occurrence instant
      (render delay/reorder does not change it) (T1–T4, FR-008a/c, SC-003a/c).
- [ ] T025 [P] [US1] `PlaylistInfoBlockTests` (NEW) in `Valistream/Valistream/ValistreamIntegrationTests/PlaylistInfoBlockTests.swift`
      — one info block per playlist at first load in normal + verbose, never repeated, omitted in quiet;
      each media block states its own protection and mixed protected/unprotected renditions are
      independent (T30–T34, SC-012/013).
- [ ] T026 [P] [US1] `NormalSessionReadabilityTests` (NEW) in `Valistream/Valistream/ValistreamIntegrationTests/NormalSessionReadabilityTests.swift`
      — a warning-free refresh yields exactly one persistent timestamped result (SC-002); a warning's
      summary+findings+evidence is one adjacent block (T11); the final summary states outcome, counts,
      elapsed time, and report path (T36); the heartbeat does not split/duplicate/blank-pad blocks (T35);
      every normal/quiet result, notice, lifecycle, and summary line leads with an outcome word from the
      FR-007a allow-set and contains no banned internal term (FR-007/007a).
- [ ] T027 [P] [US1] Extend `Valistream/Valistream/ValistreamIntegrationTests/NonInteractiveOutputTests.swift`
      — `NO_COLOR`/`--no-color`/`TERM=dumb`/redirect produce zero styling or cursor-control bytes with
      ASCII markers; at 80- and 120-column widths no severity/identity/finding/evidence is silently
      truncated and continuation lines stay with their block (T17–T21, SC-005/006).

### Implementation for User Story 1

- [ ] T028 [US1] Create `Valistream/ValistreamCore/Sources/ValistreamCore/Output/PresentationRole.swift`
      — closed role enum (`heading`/`identifier`/`success`/`progress`/`metadata`/`warning`/`error`/
      `evidencePath`/`summary`) + restrained ANSI mapping (research D4).
- [ ] T029 [US1] Extend `Valistream/ValistreamCore/Sources/ValistreamCore/Output/TerminalOutputMode.swift`
      — add `glyphStyle: GlyphStyle` and UTF-8 capability detection alongside the existing TTY/NO_COLOR/dumb
      inputs (research D5; depends T022 expectations).
- [ ] T030 [US1] Extend `Valistream/Valistream/Valistream/TerminalWriter.swift` — whole-line severity tint
      for result/finding lines, token-scoped role styling for structural context, monochrome Unicode markers
      with ASCII fallback, long-line wrapping with recognizable continuation indent, and styling fully gated
      off for non-interactive/`--json`/`NO_COLOR`/`--no-color`/`TERM=dumb` (T14–T21, C10; depends T028, T029).
- [ ] T031 [US1] Extend `Valistream/Valistream/Valistream/TerminalWriter.swift` — block-emitting writer that
      enforces the blank-line grammar (one blank between blocks, none within, collapse consecutive,
      suppress leading/trailing) and is disabled for the machine stream (T8–T13; depends T030, same file —
      sequential).
- [ ] T032 [US1] Extend `Valistream/Valistream/Valistream/StatusRenderer.swift` — timestamp every normal
      message; group output into blocks; emit one persistent result per refresh (move request/comparison/
      storage/validation detail to verbose trace); render the `PlaylistInformation` block once in
      normal+verbose via `PlaylistInfoFormatter` field groups; render lifecycle notices; render the
      prominent final summary (T36) and corrective failure messages (T37) (depends T015, T019, T028–T031;
      FR-008/017/017a/i, SC-002).
- [ ] T033 [US1] Extend `Valistream/Valistream/Valistream/ValistreamCommand.swift` — construct
      `TerminalOutputMode` with the detected `glyphStyle` and thread it to the renderer (depends T029).
- [ ] T034 [US1] Verify/adjust `Valistream/Valistream/Valistream/ProgressView.swift` — the in-place
      heartbeat stays transient and non-competing and injects no persistent blank lines (T35, FR-024).

**Checkpoint**: US1 is fully functional and independently testable — the live terminal is readable. MVP.

---

## Phase 4: User Story 2 - Find Actionable Problems Immediately (Priority: P2)

**Goal**: from quiet stdout or the Markdown report, a reviewer moves directly from any warning/error to its
playlist and evidence — quiet keeps only signal, and the report leads with the outcome, orders findings by
severity, and carries one chronological incident timeline that links (without duplicating) finding detail.

**Independent Test**: validate a multi-severity stream; capture quiet stdout (all warnings/errors/notices/
summary, zero routine/diagnostic lines, findings grouped with evidence) and open the report (outcome-first
summary, linked section order, one incident timeline excluding routine refreshes, each finding entry links
to one complete severity-grouped finding with no duplication). Regenerating yields identical timeline order.

> Builds on US1 for terminal styling (quiet findings reuse the whole-line tint/markers from T030); the
> report half (T039/T040) is independent of the terminal layer.

### Tests for User Story 2 (write first; must FAIL before impl) ⚠️

- [ ] T035 [P] [US2] `IncidentTimelineTests` in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/IncidentTimelineTests.swift`
      — ordered by `(at, sequence)`; equal timestamps preserve recorded sequence; routine successful
      refreshes excluded; finding entries are compact and link without duplicating message/evidence
      (R10–R12, SC-008a/b/c).
- [ ] T036 [P] [US2] `SessionReportTimelineInfoTests` in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/SessionReportTimelineInfoTests.swift`
      — markdown outcome-first summary (R1), linked section order (R2), findings errors→warnings→info (R3),
      ISO-8601(+offset) timestamps (R5/R6), GitHub callouts + emoji that degrade to plain text (R14/R15),
      no shields-style badges/HTML (R16), one info block per loaded playlist (R13); JSON schema v1 unchanged.
- [ ] T037 [P] [US2] `IncidentTimelineReportTests` (NEW) in `Valistream/Valistream/ValistreamIntegrationTests/IncidentTimelineReportTests.swift`
      — end-to-end timeline completeness/ordering/linking/no-duplication and deterministic regeneration
      (R8–R12, SC-008a/b/c).
- [ ] T038 [P] [US2] `QuietModeFindingsTests` (NEW) in `Valistream/Valistream/ValistreamIntegrationTests/QuietModeFindingsTests.swift`
      — quiet contains all warnings/errors/required notices/shutdown/final summary and zero routine
      success/diagnostic lines and no info block; findings grouped by playlist/snapshot with evidence
      attached (T22–T24, SC-004).

### Implementation for User Story 2

- [ ] T039 [US2] Create `Valistream/ValistreamCore/Sources/ValistreamCore/Session/IncidentTimeline.swift`
      — `IncidentTimeline`/`TimelineEntry`/`TimelineKind`, assembled from recorded events and ordered by
      `(at, sequence)`; finding entries carry a link anchor only (research D9; depends T016, T019).
- [ ] T040 [US2] Extend `Valistream/ValistreamCore/Sources/ValistreamCore/Session/SessionReportBuilder.swift`
      `buildMarkdown` — outcome-first summary; linked section order Summary → Incident Timeline → Findings →
      Playlist Information → Legend → Session Details; findings errors→warnings→info; ISO-8601(+offset)
      timestamps; the incident-timeline section (links, no duplication); per-playlist info blocks rendered
      from `PlaylistInfoFormatter` field groups; GitHub callouts + emoji icons with plain-text degradation;
      no badges/HTML. `buildJSON` schema v1 stays unchanged (R1–R16, FR-025–027a; depends T010, T015, T039).
- [ ] T041 [US2] Extend `Valistream/Valistream/Valistream/StatusRenderer.swift` — quiet-mode filtering: omit
      routine discovery/progress/successful-refresh/diagnostic messages and the info block; retain warnings,
      errors, required notices, shutdown state, and final summary; group findings by playlist/snapshot with
      adjacent evidence (T22–T24, FR-015/016; depends T032).

**Checkpoint**: US1 + US2 work independently — findings are actionable from quiet output and the report.

---

## Phase 5: User Story 3 - Diagnose Deeply Without Losing Context (Priority: P3)

**Goal**: verbose mode keeps every diagnostic category, nested under a clear playlist/snapshot context and
visually subordinate to results/findings, while findings, evidence, reports, structured output, and exit
status stay identical to normal.

**Independent Test**: compare normal vs verbose captures of the same scripted session — verbose adds every
diagnostic category under a clear context with consistent labels, subordinate to outcomes; the reported
result, evidence, report files, structured output, and exit status are identical across tiers.

> Builds on US1's terminal layer (StatusRenderer/TerminalWriter); adds the verbose tier only.

### Tests for User Story 3 (write first; must FAIL before impl) ⚠️

- [ ] T042 [P] [US3] `VerbosityEquivalenceTests` (NEW) in `Valistream/Valistream/ValistreamIntegrationTests/VerbosityEquivalenceTests.swift`
      — normal vs verbose for the same run produce identical findings, evidence, report files, structured
      output, and exit status (V3, T29, FR-021, SC-011).
- [ ] T043 [P] [US3] Extend `Valistream/Valistream/ValistreamIntegrationTests/VerboseDistinctnessTests.swift`
      — every diagnostic category is nested under a playlist/snapshot context with an unambiguous label and
      is visually subordinate to results/findings (T27/T28, SC-007).

### Implementation for User Story 3

- [ ] T044 [US3] Extend `Valistream/Valistream/Valistream/StatusRenderer.swift` — verbose tier: nest every
      diagnostic category under playlist/snapshot context using `TraceFormatter` category labels, style it
      subordinate (metadata role), and ensure it is additive only (no change to result/evidence/report/
      structured output/exit) (T27–T29, FR-019/020/021; depends T032).

**Checkpoint**: all three terminal stories are independently functional.

---

## Phase 6: User Story 4 - Start Using Valistream from the README (Priority: P4)

**Goal**: a first-time user, using only `README.md`, can understand the tool, confirm platform support,
install via a verified path, run a first validation, choose the right output mode, and find the report and
evidence. Ships version `0.4.0` with verifiable badges (incl. coverage).

**Independent Test**: hand the README to someone unfamiliar with the repo — they can determine platform
support, install through a documented path, run a first validation against the quick-start stream, explain
the output modes, and locate the report and evidence, with zero doc-vs-binary differences.

### Implementation for User Story 4

- [ ] T045 [US4] Verify `MARKETING_VERSION` = `0.4.0` for all build configurations in
      `Valistream/Valistream/Valistream.xcodeproj/project.pbxproj` (already bumped 2026-06-15; FR-001, research D13).
- [ ] T046 [US4] Verify `CommandConfiguration.version` = `0.4.0` (already set) and update `--help`/version
      discussion copy in `Valistream/Valistream/Valistream/ValistreamCommand.swift` (FR-001, readme X2; depends T033, same file).
- [ ] ~~T047 [US4] Measure release coverage via `xcrun xccov` for the README badge~~ — **REMOVED**:
      coverage badge dropped (FR-029a; no verifiable durable source). No README coverage value is measured
      for this release.
- [ ] T048 [US4] Verify the quick-start public HLS test stream resolves and runs cleanly with the `0.4.0`
      binary; capture sanitized example output for the README (FR-031/037, readme Q2; no committed
      credentials/expiring URLs).
- [ ] T049 [US4] Rewrite `README.md` (repo root) — full GitHub structure (FR-029): name/description,
      motivation, capabilities, how it works, quick start, installation, usage, option reference, output
      modes, generated artifacts, examples, exit codes, troubleshooting, limitations/platform; badges
      (license/release/platform — **no coverage badge**, B1–B2); primary `valistream-cli.zip` install + secondary source build + unsupported channels
      (I1–I3); verified quick start (Q1–Q3); option reference matching `0.4.0` `--help` (O1) and output-mode
      guidance (O2); plain-text example excerpts for quiet/normal/verbose/no-color/structured/report/session
      dir (E1–E3); exit codes 0/1/2/3/130 (X1); version `0.4.0` (X2) (depends T045–T048).
- [ ] T050 [US4] README verification pass against the `0.4.0` binary: zero diff vs `--help`/`--version`,
      exit codes, output-artifact names, and example command behavior; every displayed badge reflects a
      current verifiable value (omit if unverifiable) (SC-010, readme B2/O1/X1/X2).

**Checkpoint**: onboarding is complete and verified; all four stories delivered.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: full regression, coverage/badge finalization, styling-disabled + manual acceptance, and style
conformance across everything changed.

- [ ] T051 Full regression gate: `BuildProject` with **0** navigator warnings (`XcodeListNavigatorIssues`),
      `swift test` (package `ValistreamCoreTests`) green, and `RunAllTests` (`Valistream` scheme incl. the
      003 guards, `CompatibilityFreezeTests`, and `VerbosityEquivalenceTests`) green (V1/V2/V3, SC-011).
- [ ] T052 [P] Confirm every displayed `README.md` badge (license, release/version, platform/Swift)
      reflects a current verifiable value; omit any that cannot be verified (no coverage badge this
      release — FR-029a) (SC-010, readme B2).
- [ ] T053 [P] Styling-disabled + width validation per `specs/004-output-readability/quickstart.md`:
      `NO_COLOR`/`--no-color`/`TERM=dumb`/redirect emit zero styling/cursor bytes with ASCII markers; 80- and
      120-column widths truncate nothing essential (SC-005/006, T17–T21).
- [ ] T054 Manual acceptance with the user-supplied live "TV Nord" and VOD "NRK news" streams (conversation-
      only URLs, never committed): live roster/heartbeat/Ctrl-C, the playlist information block including
      protection on protected vs unprotected renditions, timestamps, and report readability (FR-038, readme
      A1).
- [ ] T055 Run `specs/004-output-readability/quickstart.md` end-to-end and confirm every "Done when"
      criterion passes.
- [ ] T056 [P] Conformance review of all new/changed files against `styleguide.md` and `unit-testing.md`;
      clear any serena `get_diagnostics_for_file` findings.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup; **blocks** US1/US2/US3.
- **US1 (Phase 3)**: depends on Foundational. The MVP.
- **US2 (Phase 4)**: depends on Foundational; quiet-terminal work builds on US1 (shared `StatusRenderer`/
  `TerminalWriter`); the report half is independent.
- **US3 (Phase 5)**: depends on Foundational + US1 (extends the terminal layer).
- **US4 (Phase 6)**: depends on the implemented behavior of US1–US3 (README/badges/coverage document the
  shipped `0.4.0`).
- **Polish (Phase 7)**: depends on all desired stories.

### Story dependencies

- US1 (P1): independent after Foundational — viable standalone MVP.
- US2 (P2): report independent; quiet reuses US1 terminal styling.
- US3 (P3): extends US1.
- US4 (P4): documents/verifies the released binary; needs the version verification (T045/T046).

### Key within-phase ordering

- Foundational: T011 → T012/T013 → T014 → T015; T009 → T017 → T018/T019/T020.
- US1: T028/T029 → T030 → T031 (same file, sequential) → T032; T029 → T033.
- US2: T039 → T040; T032 → T041.
- US3: T032 → T044.
- US4: T045/T046/T048 → T049 → T050.

---

## Parallel opportunities

- **Setup**: T002 ∥ T001 work.
- **Foundational tests**: T003, T004, T005, T006, T007, T008 all ∥ (distinct files).
- **Foundational impl**: T010, T011, T016 ∥ (distinct files) once T009 lands; T013 after T011.
- **US1 tests**: T021–T027 all ∥ (distinct files).
- **US2 tests**: T035–T038 all ∥. **US3 tests**: T042 ∥ T043.
- **Polish**: T052, T053, T056 ∥.

### Parallel example: Foundational tests

```text
Task: TimestampFormatterTests (Output/TimestampFormatterTests.swift)
Task: PlaylistProtectionTests (Playlist/PlaylistProtectionTests.swift)
Task: PlaylistInformationTests (Playlist/PlaylistInformationTests.swift)
Task: PlaylistInfoFormatterTests (Output/PlaylistInfoFormatterTests.swift)
Task: PlaylistLifecycleEventTests (Session/PlaylistLifecycleEventTests.swift)
Task: CompatibilityFreezeTests (ValistreamIntegrationTests/CompatibilityFreezeTests.swift)
```

---

## Implementation strategy

### MVP first (US1)

1. Phase 1 Setup → green baseline + coverage source.
2. Phase 2 Foundational → Core backbone; T008 proves frozen surfaces unchanged.
3. Phase 3 US1 → readable live terminal. **STOP and VALIDATE** independently (the MVP).

### Incremental delivery

US1 (terminal readability) → US2 (quiet + report + incident timeline) → US3 (verbose depth) → US4 (README +
`0.4.0`; no coverage badge). Each story is a testable increment; the compatibility net (T008) and the
verbosity-equivalence test (T042) keep the frozen machine surfaces and cross-tier results stable throughout.

### Notes

- `[P]` = different file, no incomplete dependency. `StatusRenderer.swift` is touched by T032/T041/T044
  across phases — sequential, not parallel.
- Tests are written first and must fail before implementation (Constitution II).
- Machine surfaces (`--json`, JSONL, JSON schema v1, `.meta.json`, selection, exit codes) are frozen —
  never edit their data/format; styling/grammar/timestamps are gated off for them (C10).
- Use repo-root filesystem paths (not Xcode navigator paths). Verify a path with serena/`XcodeGlob` before
  creating a file.
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.

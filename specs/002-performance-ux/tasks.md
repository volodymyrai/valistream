---
description: "Task list for feature 002 — Performance and UX"
---

# Tasks: Performance and UX

**Input**: Design documents from `/specs/002-performance-ux/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/)

**Tests**: Included by default per constitution Principle II (Test-First, NON-NEGOTIABLE). Write each
test before its implementation and confirm it fails first.

**Organization**: Grouped by user story (P1→P5) for independent implementation and testing.

## Path Conventions (this repo — from plan.md / serena setup)

- Core library: `Valistream/ValistreamCore/Sources/ValistreamCore/<Module>/`
- Core unit tests: `Valistream/ValistreamCore/Tests/ValistreamCoreTests/<Area>/`
- CLI tool: `Valistream/Valistream/Valistream/`
- Integration tests: `Valistream/Valistream/ValistreamIntegrationTests/`
- Xcode project: `Valistream/Valistream/Valistream.xcodeproj`

> **Testability rule (binding, see Notes)**: pure decision/formatting logic lives in **core** (unit-
> testable in `ValistreamCoreTests`); code importing **Rainbow/Promptberry** lives in the **CLI** target
> (no CLI unit-test target exists) and is verified by build + integration tests + the manual quickstart.
> Core stays **zero external dependencies**.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: executable rename + new CLI-target dependencies.

- [X] T001 Set CLI target build setting `PRODUCT_NAME = valistream` (was `$(TARGET_NAME)`→`Valistream`) in `Valistream/Valistream/Valistream.xcodeproj`; verify ArgumentParser `commandName` is already `valistream`; confirm built binary is `…/Debug/valistream` (FR-001, research D9)
- [X] T002 Add remote SwiftPM package references **Rainbow** (color) and **Promptberry** (prompts) to the CLI target in `Valistream/Valistream/Valistream.xcodeproj`; resolve and **confirm both build under Swift 6 strict concurrency + macOS 14** (research D1). If either fails to resolve/compile, record it and activate the documented fallback (in-house ANSI / retain termios checklist) — do **not** add either dependency to the `ValistreamCore` package
- [X] T003 [P] Update tool-name strings to `valistream` in the session-start banner, `--help`/`--version` surface (`Valistream/Valistream/Valistream/ValistreamCommand.swift`) and `README` (FR-001, SC-009)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: shared presentation policy + cross-story core types that US1–US5 build on. Moved here (not
into US1) so later stories don't depend on US1 — preserving story independence.

**⚠️ CRITICAL**: No user story work begins until this phase is complete.

- [X] T004 [P] Unit tests for `TerminalOutputMode` styling decision (TTY × `NO_COLOR` × `--no-color` × `TERM=dumb` → styling on/off) and `Verbosity` levels, in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Output/TerminalOutputModeTests.swift` (FR-009)
- [X] T005 [P] Implement pure, dependency-free `TerminalOutputMode` (styling gate predicate) + `Verbosity` enum (`quiet`/`normal`/`verbose`) in `Valistream/ValistreamCore/Sources/ValistreamCore/Output/TerminalOutputMode.swift` (research D2, D10) — no Rainbow import
- [X] T006 [P] Unit tests for `SessionEndReason` and the additive `SessionEvent` activity/progress case (incl. `--json` encoding stays backward-compatible) in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/SessionEventProgressTests.swift`
- [X] T007 Add `SessionEndReason { completed, gracefulStop, timeLimit }` and extend `SessionEvent` with an additive `.activity(ActivityProgress)` case + `ActivityProgress` model in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/SessionConfig.swift` (and `ValidationSessionState.swift` as needed) — additive only; existing event cases unchanged (FR-003, data-model)
- [X] T008 Implement CLI `TerminalWriter` (applies `TerminalOutputMode`: plain vs Rainbow-styled; severity text labels `ERROR`/`WARN`/`INFO`/`OK`; blank-line separation between logical messages) in `Valistream/Valistream/Valistream/TerminalWriter.swift` (FR-008, FR-009, FR-010) — depends on T002, T005

**Checkpoint**: shared output policy + core event/finalization types ready.

---

## Phase 3: User Story 1 - Follow the Session in Real Time (Priority: P1) 🎯 MVP

**Goal**: the tool stays responsive and continuously narrates current activity + overall progress;
output is color-coded by severity, blank-line separated, plain on non-TTY, and never freezes.

**Independent Test**: run against a multi-playlist VOD and a live stream; activity + counters update
sub-second throughout; severity-colored + spaced on TTY; zero control bytes when redirected (SC-004);
display never freezes during fetch/validation bursts.

### Tests for User Story 1 ⚠️ (write first, confirm they fail)

- [X] T009 [P] [US1] Integration test: non-interactive run emits plain, discrete progress lines with **zero** ANSI/cursor/animation control bytes and remains legible (SC-004, FR-007), in `Valistream/Valistream/ValistreamIntegrationTests/NonInteractiveOutputTests.swift`
- [X] T010 [P] [US1] Core unit test: a one-shot session emits `.activity(ActivityProgress)` events whose `completed`/`total` advance through fetch→validate stages (driven by `ScriptedStreamFetcher`), in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/ProgressEventsTests.swift` (FR-005)
- [X] T011 [P] [US1] Core unit test: `ProgressFormatter` renders `activity — N of M (xx%)` (and live "refreshes done") correctly across known/unknown totals, in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Output/ProgressFormatterTests.swift`

### Implementation for User Story 1

- [X] T012 [P] [US1] Implement pure `ProgressFormatter` (activity + counts/percentage formatting) in `Valistream/ValistreamCore/Sources/ValistreamCore/Output/ProgressFormatter.swift` (FR-005)
- [X] T013 [US1] Emit `.activity(ActivityProgress)` events at each stage of `ValidationSession.run()`/`monitor()`/`monitorPlaylist()` ("fetching master", "validating i of n", "monitoring live, k refreshes") without blocking the work path (FR-002, FR-005), in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift` — depends on T007
- [X] T014 [US1] Implement CLI `ProgressView`: in-place TTY status line (spinner + counts, CR + clear-to-EOL, redraw ≥1 Hz) and plain discrete lines on non-TTY (FR-006, FR-007, SC-001), in `Valistream/Valistream/Valistream/ProgressView.swift` — depends on T008, T012
- [X] T015 [US1] Update `StatusRenderer` to color findings/messages by severity via `TerminalWriter`, add blank-line spacing, and print discrete log lines above the live progress line (FR-008, FR-010), in `Valistream/Valistream/Valistream/StatusRenderer.swift` — depends on T008
- [X] T016 [US1] Add `--verbose` flag and enforce `--quiet`/`--verbose` mutual exclusion (exit 2); thread `Verbosity` into `StatusRenderer`/`ProgressView` gating (FR-011), in `Valistream/Valistream/Valistream/ValistreamCommand.swift`
- [X] T017 [US1] Run a dedicated render `Task` consuming `session.events` concurrently with the session so the display updates while work proceeds and never blocks input/interrupts (FR-002, SC-001, SC-002), in `Valistream/Valistream/Valistream/ValistreamCommand.swift` — depends on T013, T014, T015

**Checkpoint**: responsive, color-coded, spaced, narrated output on TTY; clean plain output on non-TTY. MVP shippable.

---

## Phase 4: User Story 2 - Stop a Live Session Without Losing Work (Priority: P2)

**Goal**: any in-progress session (live or one-shot) can be gracefully stopped — in-flight requests
cancelled immediately, archive flushed, a complete (live) or partial (one-shot) report finalized — with
a second interrupt forcing immediate exit; time-limit and normal completion use the same clean path.

**Independent Test**: start a live session, let several refreshes occur, graceful-stop → clean shutdown
with complete report + flushed archive ≤3 s; second interrupt during shutdown → immediate exit 130;
one-shot stop → PARTIAL report; `--limit` expiry finalizes via the same path.

### Tests for User Story 2 ⚠️ (write first, confirm they fail)

- [X] T018 [P] [US2] Integration test: live graceful stop finalizes a complete report + flushed archive and shuts down ≤3 s (SC-003); a second interrupt forces exit 130 (FR-013), in `Valistream/Valistream/ValistreamIntegrationTests/GracefulStopTests.swift`
- [X] T019 [P] [US2] Integration test: one-shot (VOD) graceful stop finalizes a report clearly marked **PARTIAL** covering playlists validated so far (FR-012, clarification), in `Valistream/Valistream/ValistreamIntegrationTests/OneShotInterruptTests.swift`
- [X] T020 [P] [US2] Core unit test: `finish(reason:)` records the correct `SessionEndReason` and marks one-shot graceful-stop reports partial; cancelled in-flight fetches recorded as aborted/incomplete; **a graceful stop requested during startup (before any fetch) still finalizes cleanly and writes an early-stop report** (spec §Edge Cases), in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/FinalizationTests.swift`

### Implementation for User Story 2

- [X] T021 [US2] Unify finalization into `finish(reason: SessionEndReason)` — single path for `completed`/`gracefulStop`/`timeLimit`: cancel in-flight network tasks immediately (cancel the monitoring `TaskGroup`/per-fetch tasks), flush `SessionArchive` + `FindingsLog`, record cancelled fetches as aborted/incomplete, finalize report, set state (FR-012, FR-014, SC-003), in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift` — depends on T007
- [X] T022 [US2] Make one-shot `run()` check `stopRequested` between playlists and finalize via `finish(.gracefulStop)` (partial) (FR-012), in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift` — depends on T021
- [X] T023 [US2] Route optional time-limit expiry through `finish(.timeLimit)` so it converges on the same clean path (FR-014), in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift` — depends on T021
- [X] T024 [US2] Implement two-stage SIGINT in the CLI: 1st interrupt requests graceful stop and prints a shutdown notice warning that a second interrupt forces exit; 2nd interrupt calls `_exit(130)`; on clean finish, confirm final report + artifact paths (FR-013, FR-015), in `Valistream/Valistream/Valistream/ValistreamCommand.swift` (extend `installSignalHandlers`)

**Checkpoint**: US1 + US2 both work; graceful stop is bounded and lossless across all end paths.

---

## Phase 5: User Story 3 - Control Where Artifacts and Reports Are Written (Priority: P3)

**Goal**: `--output` chooses the base directory; the absolute per-session path is printed before any
fetch; each session gets a unique subfolder; unwritable targets fail fast.

**Independent Test**: run with and without `--output`; absolute session path printed at startup in both
cases; artifacts land in a unique per-session subfolder under the chosen base; a second run doesn't
overwrite the first; an unwritable `--output` fails fast before fetching.

### Tests for User Story 3 ⚠️ (write first, confirm they fail)

- [X] T025 [P] [US3] Core unit test: `OutputLocation` resolves relative→absolute, applies the default base (`~/.valistream/sessions/`), produces a unique per-session subfolder, and throws an actionable error when the base is unwritable (FR-016, FR-018, FR-019, FR-020), in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/OutputLocationTests.swift`
- [X] T026 [P] [US3] Integration test: startup prints the absolute session folder path **before** fetching, and an unwritable `--output` fails fast (exit 2) before any fetch (FR-017, FR-019, SC-005), in `Valistream/Valistream/ValistreamIntegrationTests/OutputLocationStartupTests.swift`

### Implementation for User Story 3

- [X] T027 [P] [US3] Implement `OutputLocation` resolver — absolute base (relative resolved vs CWD), default `~/.valistream/sessions/` on macOS / platform data dir elsewhere, unique `<base>/<sessionID>` subfolder, writability pre-flight (FR-016, FR-018, FR-020, research D5), in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/OutputLocation.swift`
- [X] T028 [US3] Wire `OutputLocation` into session startup: resolve + pre-flight-create + verify writable **before** fetching; use the resolved `sessionFolder` for archive/reports (FR-018, FR-019), in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift` — depends on T027
- [X] T029 [US3] CLI: print the absolute session folder path at startup before fetch; map a pre-flight failure to a fail-fast exit-2 error with an actionable message (FR-017, FR-019), in `Valistream/Valistream/Valistream/ValistreamCommand.swift` — depends on T028

**Checkpoint**: predictable, discoverable, collision-free output locations.

---

## Phase 6: User Story 4 - A Report That's Always Current and Easy to Read (Priority: P4)

**Goal**: both reports stay current during live monitoring (atomic, ≤1 cycle stale); the human report
is prettified and refers to playlists by stable aliases with a resolving legend; the JSON schema is
unchanged.

**Independent Test**: during a live session, open the on-disk reports at several points — always
current and complete/openable; final markdown is prettified, body uses aliases only (no raw URLs),
every alias resolves via the legend; JSON validates against feature 001's frozen schema.

### Tests for User Story 4 ⚠️ (write first, confirm they fail)

- [ ] T030 [P] [US4] Core unit test: `PlaylistAlias`/`AliasRegistry` — role+attribute derivation (`video-1080p`/`audio-en`/`subs-en`/`iframe-720p`), indexed fallback (`V1`/`A1`/`S1`/`I1`), deterministic dedup suffix, and stability (same URL → same alias) (FR-024, FR-026), in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/PlaylistAliasTests.swift`
- [ ] T031 [P] [US4] Core unit test: prettified `buildMarkdown` has the required sections, groups findings by severity then category, contains **zero raw playlist URLs** outside the legend, and every alias in the body resolves via the legend (FR-023, FR-024, FR-025, SC-007), in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/ReportMarkdownTests.swift`
- [ ] T032 [P] [US4] Core unit test: `buildJSON` output validates against the frozen 001 schema with no added/removed/renamed fields (FR-003, FR-021, SC-010), in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/ReportJSONSchemaTests.swift`
- [ ] T033 [P] [US4] Core unit test: atomic report write (temp file + replace) always yields a complete, valid document — never a partial read (FR-022), in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Archive/AtomicReportWriteTests.swift`
- [ ] T034 [P] [US4] Integration test: a live session rewrites both reports once per refresh cycle; opening either at any point yields a current (≤1 cycle stale), complete, openable document (FR-021, SC-006), in `Valistream/Valistream/ValistreamIntegrationTests/LiveReportFreshnessTests.swift`

### Implementation for User Story 4

- [ ] T035 [P] [US4] Implement `PlaylistAlias` + `AliasRegistry` (deterministic, stable, session-unique; dedup suffixing) in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/PlaylistAlias.swift` (data-model, FR-024–026)
- [ ] T036 [US4] Rewrite `SessionReportBuilder.buildMarkdown` — header/summary/legend/findings(by severity→category)/per-playlist sections, aligned/tabular summaries, aliases-only body + resolving legend; leave `buildJSON` schema-identical (FR-023, FR-024, FR-025, FR-003), in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/SessionReportBuilder.swift` — depends on T035
- [ ] T037 [US4] Add an atomic report-write helper (write temp in same dir + `FileManager.replaceItemAt`) used for both report files (FR-022), in `Valistream/ValistreamCore/Sources/ValistreamCore/Archive/SessionArchive.swift`
- [ ] T038 [US4] Drive per-refresh-cycle coalesced atomic writes of **both** reports during `monitor()` (dirty-flag, single write per cycle); one-shot writes at completion and on graceful stop (FR-021, FR-022, SC-006), in `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift` — depends on T036, T037
- [ ] T039 [US4] Assign aliases at playlist discovery via the idempotent `AliasRegistry` so the report (T036) and progress share one stable mapping (FR-026); **optionally** surface the alias as `aliasInScope` in `.activity` events for nicer status text (FR-005, US1 integration). US4's aliased report does **not** require this task — `buildMarkdown` resolves aliases lazily through the idempotent registry — so US4 stays independently shippable (Principle IV). In `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift` — depends on T035; the `.activity` surface additionally depends on T013

**Checkpoint**: continuously fresh, atomic, prettified, aliased reports; JSON schema unchanged.

---

## Phase 7: User Story 5 - Polished Interactive Prompts (Priority: P5)

**Goal**: the playlist-selection step uses a polished multi-select (arrow nav, space toggle, all
pre-selected, hints); it is skipped when non-interactive or a selection was supplied; cancelling
restores the terminal and exits cleanly.

**Independent Test**: interactive run shows a navigable multi-select with clear affordances; `--all`
or non-TTY run shows no prompt and applies the default; Ctrl-C during the prompt restores the terminal
and exits cleanly.

### Tests for User Story 5 ⚠️ (write first, confirm they fail)

- [ ] T040 [P] [US5] Core unit test: prompt-skip policy — non-TTY **or** a supplied selection (`--select`/`--all`) ⇒ skip prompt and apply the documented default (all) (FR-028), in `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/SelectionPromptPolicyTests.swift`
- [ ] T041 [P] [US5] Integration test: `--all` and non-TTY runs display **no** prompt and apply the default selection, preserving scriptability (FR-028), in `Valistream/Valistream/ValistreamIntegrationTests/PromptSkipTests.swift`

### Implementation for User Story 5

- [ ] T042 [US5] Implement `PromptberrySelection` multi-select (arrow navigation, space toggle, all pre-selected, on-screen hints, clear selection state) (FR-027), in `Valistream/Valistream/Valistream/PromptberrySelection.swift` — depends on T002; if Promptberry is unavailable, retain the existing `PlaylistChecklist` as the fallback path (research D1/D8)
- [ ] T043 [US5] Wire the selection step: skip when non-TTY or `--select`/`--all` supplied (default all); restore the terminal to a sane state and exit cleanly with a message on cancel/interrupt (FR-028, FR-029), in `Valistream/Valistream/Valistream/ValistreamCommand.swift` — depends on T042

**Checkpoint**: all five stories independently functional.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T044 [P] Hide or remove the inert `--segments`/`--tolerance` flags (deferred work — spec §Out of scope) so they are not advertised, in `Valistream/Valistream/Valistream/ValistreamCommand.swift` (contracts/cli-interface)
- [ ] T045 [P] Edge cases: graceful truncation/wrapping of long URLs/paths on narrow terminals and degrade-to-plain when the terminal can't render color (spec §Edge Cases), in `Valistream/Valistream/Valistream/TerminalWriter.swift` + `ProgressView.swift`
- [ ] T046 [P] Update `README` and help text to document every new option (`--output`, `--verbose`, `--no-color`) and the `valistream` name (FR-004, SC-009)
- [ ] T047 Style/test compliance pass on all new code against `styleguide.md` and `unit-testing.md` (repo root)
- [ ] T048 Regression gate: `swift test` (unit/conformance) + `Valistream.xctestplan` (integration via Xcode scheme) all green; confirm exit codes and JSON report schema unchanged vs feature 001 (FR-003, SC-010) — pipe builds/tests through `xcsift`
- [ ] T049 Execute [quickstart.md](quickstart.md) end-to-end against a real multi-playlist VOD and a live stream (US1–US5 scenarios, incl. SC-001/003/004/005/006/007/009); also run the **manual** checks: SC-008 (an unfamiliar user locates a named finding in the report in < 30 s) and FR-029 (Ctrl-C while the selection prompt is open restores the terminal and exits cleanly)

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)** → no deps; T001 before T002 (both edit the `.xcodeproj`); T003 [P].
- **Foundational (Phase 2)** → after Setup; **blocks all user stories**.
- **User Stories (Phase 3–7)** → after Foundational. Recommended priority order P1→P2→P3→P4→P5; each is
  independently testable. (Spec notes US2 reads best on top of US1's live loop, but US2's core
  finalization is independently testable.)
- **Polish (Phase 8)** → after the targeted stories are complete.

### ⚠️ Shared hot file — `ValidationSession.swift`

Tasks **T013, T021, T022, T023, T028, T038, T039** all edit
`Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift`. They are **not [P]
with each other**, even across stories — serialize edits to this file (suggested order:
T013 → T021 → T022 → T023 → T028 → T038 → T039).

### Within each story

- Tests first, confirm they fail, then implement.
- Core models/policies before core wiring; core before CLI; CLI core before CLI integration/render loop.

### Parallel opportunities

- Setup: T003 [P] alongside T001/T002 wiring.
- Foundational: T004 + T005 + T006 [P] (different files); T007/T008 follow.
- After Foundational, different stories can proceed in parallel **except** for the shared
  `ValidationSession.swift` serialization above.
- All `[P]` test tasks within a story run together; pure-core `[P]` impl (T012, T027, T035) run
  alongside their story's CLI work.

---

## Parallel Example: User Story 4 tests

```bash
# Launch US4 tests together (different files), before implementation:
Task: "PlaylistAlias/AliasRegistry unit tests …/Session/PlaylistAliasTests.swift"
Task: "Prettified markdown / no-raw-URL / legend tests …/Session/ReportMarkdownTests.swift"
Task: "buildJSON frozen-schema test …/Session/ReportJSONSchemaTests.swift"
Task: "Atomic report write test …/Archive/AtomicReportWriteTests.swift"
Task: "Live report freshness integration test …/ValistreamIntegrationTests/LiveReportFreshnessTests.swift"
```

---

## Implementation Strategy

### MVP first (US1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational → 3. Phase 3 US1 → **STOP & validate** (responsive, colored,
   spaced, narrated output; clean non-TTY) → demo.

### Incremental delivery

Foundation → US1 (MVP) → US2 (graceful stop) → US3 (output dir) → US4 (live/aliased report) → US5
(prompt). Each adds value without breaking prior stories; stop at any checkpoint to validate.

---

## Notes

- **Core stays dependency-free.** Rainbow/Promptberry attach to the CLI target only (T002). Pure
  decision/formatting logic (`TerminalOutputMode`, `Verbosity`, `ProgressFormatter`, `PlaylistAlias`,
  `OutputLocation`, `SessionEndReason`) lives in core and is unit-tested in `ValistreamCoreTests`.
- **No CLI unit-test target exists.** CLI types that import Rainbow/Promptberry or do in-place terminal
  rendering (`TerminalWriter`, `ProgressView`, `PromptberrySelection`) are verified via integration
  tests (observable behavior) + the manual quickstart (T049). Interactive prompt UX and live in-place
  rendering are not headlessly unit-testable.
- **Frozen (do not change)**: JSON report schema, validation rule sets/IDs, exit-code contract
  (FR-003, SC-010). US4 changes report *write timing/formatting* and the *markdown* only.
- Build/test via xcode-tools (`BuildProject`, `RunSomeTests`); pipe `swift build`/`swift test` through
  `xcsift`. Use **serena** for code inspection/edit; **xcode-tools** `DocumentationSearch` for docs —
  **no WebSearch**.
- Commit after each task or logical group. `[P]` = different files, no incomplete-task dependency.

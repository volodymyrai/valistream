---

description: "Task list for HLS Stream Validator implementation"
---

# Tasks: HLS Stream Validator

**Input**: Design documents from `/specs/001-hls-stream-validator/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: INCLUDED (constitution Principle II — Test-First, spec did not waive). Within each phase,
test tasks MUST be written first and observed failing before the corresponding implementation tasks.

**Implementation Guidance (binding — from plan.md)**:

- Code style: follow `styleguide.md` (repo root) for ALL Swift code.
- Test code: follow `unit-testing.md` (repo root) for ALL test development.
- Consult skills before writing the corresponding code: `swift-testing-pro` (tests),
  `swift-concurrency-pro` (actors/TaskGroup/AsyncStream), `swift-api-design-guidelines`
  (public API of ValistreamCore), `swift-architecture` (module/layer decisions), `swift-language`
  (core idioms).
- Pipe `swift build` / `swift test` through `xcsift` for build/test log analysis.
- No local HTTP server in tests — integration tests use the scripted `StreamFetching` stub
  (research.md §8).

**Organization**: Tasks grouped by user story (spec.md): US1 = one-shot validation (P1),
US2 = live monitoring (P2), US3 = session archive (P3), US4 = segment bandwidth audit (P4).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

Single SwiftPM package at repository root (plan.md Project Structure):
`Sources/ValistreamCore/…` (library), `Sources/valistream/…` (CLI executable),
`Tests/ValistreamCoreTests/…` (unit/conformance), `Tests/ValistreamIntegrationTests/…` (integration).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: SwiftPM package skeleton that compiles and tests green (empty)

- [ ] T001 Create `Package.swift` (swift-tools-version 6.0, platform macOS 14): targets
      `ValistreamCore` (library), `valistream` (executable, depends on core +
      `swift-argument-parser`), `ValistreamCoreTests`, `ValistreamIntegrationTests`
- [ ] T002 Create source-tree skeleton with placeholder files per plan.md structure:
      `Sources/ValistreamCore/{Playlist,Validation,Monitoring,Networking,Archive,Segments,Session}/`,
      `Sources/valistream/`, `Tests/ValistreamCoreTests/Fixtures/`,
      `Tests/ValistreamIntegrationTests/Support/`
- [ ] T003 Verify toolchain: `swift build 2>&1 | xcsift` and `swift test 2>&1 | xcsift` succeed on
      the empty skeleton

**Checkpoint**: Package compiles; CI-able baseline exists

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Lossless M3U8 parsing, finding model, transport seam, clock seam, session skeleton —
everything every story builds on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 [P] Write tokenizer tests (line-level fidelity, attribute-list grammar incl. quoting,
      malformed/unknown/duplicate tags preserved as events, line numbers) in
      `Tests/ValistreamCoreTests/Playlist/M3U8TokenizerTests.swift`
- [ ] T005 [P] Write playlist model/builder tests (master vs media auto-detection per FR-002,
      attribute extraction, relative URI resolution) in
      `Tests/ValistreamCoreTests/Playlist/PlaylistBuilderTests.swift`
- [ ] T006 Implement lossless M3U8 tokenizer in
      `Sources/ValistreamCore/Playlist/M3U8Tokenizer.swift` (research.md §2: token stream preserves
      raw lines, numbers, anomalies)
- [ ] T007 Implement playlist model + builder (master/media models, declared attributes,
      `SegmentRef` entries, URI resolution) in `Sources/ValistreamCore/Playlist/PlaylistModel.swift`
      and `Sources/ValistreamCore/Playlist/PlaylistBuilder.swift` (data-model.md PlaylistDescriptor,
      PlaylistRefresh fields)
- [ ] T008 [P] Implement `Finding` types (severity, category, source, ruleId, location, context —
      data-model.md Finding) with encoding tests in
      `Sources/ValistreamCore/Validation/Finding.swift` and
      `Tests/ValistreamCoreTests/Validation/FindingTests.swift`
- [ ] T009 [P] Implement `StreamFetching` protocol + `FetchResult`/`ArtifactRecord` value types
      (full request/response metadata incl. redirect chain — data-model.md ArtifactRecord) in
      `Sources/ValistreamCore/Networking/StreamFetching.swift`
- [ ] T010 Implement URLSession-backed fetcher (`URLSessionTaskMetrics` capture: remote IP/port,
      timestamps, protocol; per-hop redirect recording; URLCache disabled — research.md §3) in
      `Sources/ValistreamCore/Networking/URLSessionStreamFetcher.swift`
- [ ] T011 [P] Implement `ScriptedStreamFetcher` test stub + scenario timeline support (VOD map,
      live sliding-window script advanced by test clock, error/redirect/stall/regression steps —
      research.md §8) in `Tests/ValistreamIntegrationTests/Support/ScriptedStreamFetcher.swift`
- [ ] T012 [P] Adopt injectable `Clock` (generic over `Clock<Duration>`) convention in core +
      `ManualClock` test support in `Tests/ValistreamIntegrationTests/Support/ManualClock.swift`
      (research.md §9)
- [ ] T013 [P] Write session state-machine tests (transitions per data-model.md lifecycle incl.
      aborted/failed paths, empty-selection short-circuit) in
      `Tests/ValistreamCoreTests/Session/ValidationSessionStateTests.swift`
- [ ] T014 Implement `ValidationSession` actor skeleton (state machine, config, event
      `AsyncStream` for status/findings — research.md §9) in
      `Sources/ValistreamCore/Session/ValidationSession.swift`

**Checkpoint**: Parser round-trips fixtures; transport + clock seams exist; session skeleton drives
state transitions — user story implementation can begin

---

## Phase 3: User Story 1 - On-Demand Stream Structure Validation (Priority: P1) 🎯 MVP

**Goal**: One-shot validation of master + all media playlists against RFC 8216 + Apple authoring
rules, categorized findings, CLI with meaningful exit codes

**Independent Test**: Run CLI against conformant VOD fixture stream → zero errors, exit 0; against
seeded-violation fixtures → each violation reported with rule + location, exit 1 (quickstart
scenarios 1–2)

### Tests for User Story 1 (write FIRST, ensure they FAIL) ⚠️

- [ ] T015 [P] [US1] Build conformant fixture corpus (modeled on Apple reference streams: multivariant
      master, video/audio/subtitle/I-frame playlists, VOD + event + live forms) in
      `Tests/ValistreamCoreTests/Fixtures/conformant/` + corpus runner test asserting zero
      error/warning findings in `Tests/ValistreamCoreTests/Conformance/ConformantCorpusTests.swift`
- [ ] T016 [P] [US1] Build seeded-violation fixtures for RFC 8216 master-playlist rules (one
      violation family per file: missing/duplicate required tags, bad attribute values, unresolvable
      group references) in `Tests/ValistreamCoreTests/Fixtures/violations/master/` + expected-finding
      assertions (ruleId, severity, line) in
      `Tests/ValistreamCoreTests/Conformance/MasterViolationTests.swift`
- [ ] T017 [P] [US1] Build seeded-violation fixtures for RFC 8216 media-playlist rules (target
      duration violations, sequence tags, endlist anomalies, segment duration overruns) in
      `Tests/ValistreamCoreTests/Fixtures/violations/media/` + assertions in
      `Tests/ValistreamCoreTests/Conformance/MediaViolationTests.swift`
- [ ] T018 [P] [US1] Build seeded-violation fixtures for Apple authoring rules (ladder gaps/dupes,
      missing CODECS/RESOLUTION/AVERAGE-BANDWIDTH, missing I-frame playlists, inconsistent rendition
      groups, missing EXT-X-INDEPENDENT-SEGMENTS — research.md §5 list) in
      `Tests/ValistreamCoreTests/Fixtures/violations/authoring/` + assertions in
      `Tests/ValistreamCoreTests/Conformance/AuthoringViolationTests.swift`
- [ ] T019 [P] [US1] Write integration tests: one-shot VOD session over `ScriptedStreamFetcher` —
      happy path (classification `vod`, all media fetched+validated, completion summary), LL-HLS
      tags → info finding (FR-017), encrypted stream → info finding (FR-013) in
      `Tests/ValistreamIntegrationTests/OneShotSessionTests.swift`
- [ ] T020 [P] [US1] Write integration tests: delivery failures — unreachable URL, non-playlist
      body, HTTP error status, redirect chain recorded, direct media-playlist URL standalone
      validation (FR-002/FR-014, US1 acceptance 3–4) in
      `Tests/ValistreamIntegrationTests/DeliveryFailureTests.swift`

### Implementation for User Story 1

- [ ] T021 [US1] Implement rule engine: `ValidationRule` protocol, rule registry, evaluation context
      (playlist + token stream + session info), rule metadata (id, source, default severity) in
      `Sources/ValistreamCore/Validation/RuleEngine.swift`
- [ ] T022 [P] [US1] Implement RFC 8216 master-playlist rule set in
      `Sources/ValistreamCore/Validation/Rules/RFC8216MasterRules.swift`
- [ ] T023 [P] [US1] Implement RFC 8216 media-playlist rule set in
      `Sources/ValistreamCore/Validation/Rules/RFC8216MediaRules.swift`
- [ ] T024 [P] [US1] Implement Apple authoring playlist-observable rule set (research.md §5) in
      `Sources/ValistreamCore/Validation/Rules/AppleAuthoringRules.swift`
- [ ] T025 [US1] Implement stream classification (vod/event/live per FR-005) + LL-HLS and
      encryption detection info findings (FR-013/FR-017) in
      `Sources/ValistreamCore/Validation/StreamClassifier.swift`
- [ ] T026 [US1] Implement media-playlist enumeration + fetch with delivery-finding conversion
      (FR-004/FR-014: timeouts/HTTP errors/non-playlist bodies → `delivery` findings, session
      continues) in `Sources/ValistreamCore/Session/PlaylistLoader.swift`
- [ ] T027 [US1] Wire one-shot flow into `ValidationSession` (fetchingMaster → validatingInitial →
      finishing → completed; findings emitted on event stream) in
      `Sources/ValistreamCore/Session/ValidationSession.swift`
- [ ] T028 [US1] Implement CLI v1 in `Sources/valistream/ValistreamCommand.swift` +
      `Sources/valistream/StatusRenderer.swift`: argument parsing (URL, `--output-dir` accepted but
      archive lands in US3), live status + findings rendering (FR-009), exit codes 0/1/2/3 per
      contracts/cli-interface.md. Verify quickstart scenarios 1–2 manually.

**Checkpoint**: US1 fully functional — conformance corpus green, CLI validates real streams, MVP
deliverable

---

## Phase 4: User Story 2 - Live Stream Monitoring & Continuity (Priority: P2)

**Goal**: Player-accurate refresh cadence per selected playlist, continuity/staleness findings,
interactive playlist checklist, graceful stop

**Independent Test**: Scripted healthy live scenario refreshes on cadence with zero errors; scripted
stalling/regressing scenarios produce the exact expected findings; checklist + `--select`/`--all`
narrow monitoring (quickstart scenarios 3–4)

### Tests for User Story 2 (write FIRST, ensure they FAIL) ⚠️

- [ ] T029 [P] [US2] Write cadence scheduler tests with `ManualClock` (RFC 8216 §6.3.4: initial
      reload after target duration, unchanged → half-TD backoff, never faster — research.md §4) in
      `Tests/ValistreamCoreTests/Monitoring/RefreshSchedulerTests.swift`
- [ ] T030 [P] [US2] Write continuity checker tests (media sequence regression, retroactive segment
      mutation, premature head removal, discontinuity-sequence consistency — FR-007, data-model.md
      continuity rules) in `Tests/ValistreamCoreTests/Monitoring/ContinuityCheckerTests.swift`
- [ ] T031 [P] [US2] Write staleness detector tests (warning > 1.5× TD, error > 3× TD, stale
      duration in finding context) in
      `Tests/ValistreamCoreTests/Monitoring/StalenessDetectorTests.swift`
- [ ] T032 [P] [US2] Write selection resolution tests (`--select` pattern matching by id/group/
      name/URL substring, `--all`, non-TTY auto-default, empty selection → finish with note —
      FR-018) in `Tests/ValistreamCoreTests/Session/PlaylistSelectionTests.swift`
- [ ] T033 [P] [US2] Write integration test: healthy live scenario (sliding window advanced by
      `ManualClock`, all selected playlists refresh on cadence, stop → graceful summary covering
      monitored period) in `Tests/ValistreamIntegrationTests/LiveMonitoringTests.swift`
- [ ] T034 [P] [US2] Write integration tests: stalling playlist (warning then error with durations),
      sequence-regressing playlist (continuity error), discontinuity insertion (info + tracking
      continues), time-limit expiry (FR-015) in
      `Tests/ValistreamIntegrationTests/LiveFaultScenarioTests.swift`

### Implementation for User Story 2

- [ ] T035 [US2] Implement `RefreshScheduler` (per-playlist cadence state, Clock-driven, change/
      no-change backoff) in `Sources/ValistreamCore/Monitoring/RefreshScheduler.swift`
- [ ] T036 [P] [US2] Implement `ContinuityChecker` (refresh n-1 vs n rules) in
      `Sources/ValistreamCore/Monitoring/ContinuityChecker.swift`
- [ ] T037 [P] [US2] Implement `StalenessDetector` in
      `Sources/ValistreamCore/Monitoring/StalenessDetector.swift`
- [ ] T038 [US2] Wire monitoring into `ValidationSession`: `TaskGroup` per selected playlist,
      re-validation each refresh (rules + continuity), cancellation-safe stop, `--limit` expiry,
      per-playlist `monitorState` updates on event stream in
      `Sources/ValistreamCore/Session/ValidationSession.swift`
- [ ] T039 [US2] Implement playlist selection: selection model + non-interactive resolution in
      `Sources/ValistreamCore/Session/PlaylistSelection.swift`; interactive checkbox checklist
      (termios raw mode: arrows/space/enter/`a`; numbered-list fallback when raw mode unavailable —
      research.md §7) in `Sources/valistream/PlaylistChecklist.swift`
- [ ] T040 [US2] Extend CLI: live status rendering (per-playlist monitor state, finding counts),
      SIGINT/SIGTERM graceful stop → exit 130, `--json` JSON Lines output mode + `--quiet`
      (contracts/cli-interface.md output streams). Verify quickstart scenarios 3–4 manually.

**Checkpoint**: US1 + US2 work independently — live troubleshooting usable end-to-end

---

## Phase 5: User Story 3 - Session Artifact Archive (Priority: P3)

**Goal**: Per-session folder with verbatim bodies + metadata sidecars for every request, crash-safe
findings log, schema-versioned reports

**Independent Test**: Any session leaves a complete archive; every reported request has body +
sidecar with all FR-011 fields; Ctrl-C mid-session preserves everything collected (quickstart
scenario 6)

### Tests for User Story 3 (write FIRST, ensure they FAIL) ⚠️

- [ ] T041 [P] [US3] Write archive layout/writer tests (folder naming, `playlists/<id>/NNNNNN.m3u8`
      zero-padded refresh bodies, byte-exact bodies, sidecar `.meta.json` field completeness per
      FR-011 incl. redirect chain) in `Tests/ValistreamCoreTests/Archive/SessionArchiveTests.swift`
- [ ] T042 [P] [US3] Write findings-log tests (JSONL append-only, parseable after simulated abort
      mid-write) in `Tests/ValistreamCoreTests/Archive/FindingsLogTests.swift`
- [ ] T043 [P] [US3] Write report tests: `report.json` validates against
      `specs/001-hls-stream-validator/contracts/session-report.schema.json` (bundle schema as test
      resource), `report.md` renders all sections, monitored/excluded playlists recorded (FR-016/
      FR-018) in `Tests/ValistreamCoreTests/Session/SessionReportTests.swift`
- [ ] T044 [P] [US3] Write disk-space watcher tests (injected capacity provider: warn < 5 GB
      finding, clean stop < 500 MB — research.md §11) in
      `Tests/ValistreamCoreTests/Archive/DiskSpaceWatcherTests.swift`
- [ ] T045 [P] [US3] Write integration test: session interrupted mid-monitoring preserves all
      artifacts collected so far + final interrupted-marked report (US3 acceptance 3) in
      `Tests/ValistreamIntegrationTests/InterruptedSessionTests.swift`

### Implementation for User Story 3

- [ ] T046 [US3] Implement `SessionArchive` writer (session folder layout per data-model.md, serial
      write executor, verbatim bodies, `session.json` state snapshots) in
      `Sources/ValistreamCore/Archive/SessionArchive.swift`
- [ ] T047 [P] [US3] Implement `FindingsLog` JSONL appender in
      `Sources/ValistreamCore/Archive/FindingsLog.swift`
- [ ] T048 [P] [US3] Implement `DiskSpaceWatcher` (`volumeAvailableCapacityForImportantUsage`,
      thresholds, periodic check on archive flush) in
      `Sources/ValistreamCore/Archive/DiskSpaceWatcher.swift`
- [ ] T049 [US3] Implement session report builder (`report.json` per schema incl. cadence adherence
      + staleness episodes + artifact index; human `report.md`) in
      `Sources/ValistreamCore/Session/SessionReportBuilder.swift`
- [ ] T050 [US3] Wire archive into session lifecycle: every fetch archived (SC-004), findings
      streamed to JSONL, reports written on completed/aborted/failed, storage failure → alert +
      clean stop (edge case), CLI prints session folder path at end. Verify quickstart scenario 6
      manually.

**Checkpoint**: Sessions leave complete shareable evidence folders

---

## Phase 6: User Story 4 - Segment Bandwidth Verification (Priority: P4)

**Goal**: Opt-in download of all referenced segments with measured-vs-declared bandwidth findings

**Independent Test**: Scripted VOD with known segment sizes — only segments beyond tolerance
flagged; encrypted segments size-checked without decode; default sessions download zero segment
bodies (quickstart scenario 5)

### Tests for User Story 4 (write FIRST, ensure they FAIL) ⚠️

- [ ] T051 [P] [US4] Write bandwidth audit unit tests (implied bitrate math, exact tolerance
      boundary at 10% default + custom `--tolerance`, AVERAGE-BANDWIDTH vs BANDWIDTH comparison
      basis) in `Tests/ValistreamCoreTests/Segments/SegmentAuditorTests.swift`
- [ ] T052 [P] [US4] Write integration tests: segment mode VOD (all selected playlists' segments
      downloaded + archived, oversized flagged), live newly-published-segment tracking, encrypted
      stream (no decode, size checks run, info finding), segment 404/timeout → delivery finding,
      segment mode off → zero segment downloads (US4 acceptance 1–4) in
      `Tests/ValistreamIntegrationTests/SegmentModeTests.swift`

### Implementation for User Story 4

- [ ] T053 [US4] Implement `SegmentAuditor` (download via `StreamFetching`, measure bytes, implied
      bitrate vs declared, verdicts per data-model.md SegmentRecord) in
      `Sources/ValistreamCore/Segments/SegmentAuditor.swift`
- [ ] T054 [US4] Wire segment auditing into session: VOD = all segments of selected playlists after
      initial validation; live = newly published segments per refresh; segment artifacts into
      `segments/<playlist-id>/` (FR-012, Clarifications #4/#6) in
      `Sources/ValistreamCore/Session/ValidationSession.swift`
- [ ] T055 [US4] Extend CLI + report: `--segments`, `--tolerance <percent>` flags; `segmentAudit`
      section in report.json/md (schema already defines it). Verify quickstart scenario 5 manually.

**Checkpoint**: All four user stories independently functional

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T056 [P] Audit every rule's finding message for actionability (rule id + resource + location +
      what/why/expected — SC-005/SC-006) across `Sources/ValistreamCore/Validation/Rules/`
- [ ] T057 [P] Add large-stream scripted test (≥ 20 playlists) asserting one-shot completion and
      bounded scheduling drift at test scale (SC-001/SC-003 proxies) in
      `Tests/ValistreamIntegrationTests/ScaleTests.swift`
- [ ] T058 [P] Compliance pass: `styleguide.md` over `Sources/`, `unit-testing.md` over `Tests/`
      (naming, structure, doc comments per swift-api-design-guidelines for public core API)
- [ ] T059 [P] Write `README.md` (install, usage, flags, exit codes, session folder anatomy —
      derived from quickstart.md + contracts/cli-interface.md)
- [ ] T060 Full manual quickstart run-through (scenarios 1–6) against real streams; record results +
      deviations in `specs/001-hls-stream-validator/quickstart.md` verification checklist

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — BLOCKS all user stories
- **US1 (Phase 3)**: depends on Foundational
- **US2 (Phase 4)**: depends on Foundational + US1's rule engine (T021) for per-refresh
  re-validation; monitoring components (T029–T037) independent of US1
- **US3 (Phase 5)**: depends on Foundational + US1's session flow (T027); independent of US2
  (archives one-shot sessions just fine)
- **US4 (Phase 6)**: depends on US1 (selection of playlists + session flow); live-segment tracking
  part (T054) depends on US2's monitoring loop
- **Polish (Phase 7)**: depends on desired stories complete

### Within Each User Story

- Test tasks first; confirm failing before implementation (constitution Principle II)
- Rules/components before session wiring; session wiring before CLI surface
- Story complete (tests green + manual checkpoint) before next priority

### Parallel Opportunities

- Phase 2: T004, T005 together; then T008, T009, T011, T012, T013 in parallel after T006/T007
- US1: all test tasks T015–T020 in parallel; rule sets T022–T024 in parallel after T021
- US2: all test tasks T029–T034 in parallel; T036, T037 in parallel after T035
- US3: all test tasks T041–T045 in parallel; T047, T048 in parallel after T046
- Different stories CAN be parallelized by different agents after their dependency tasks land
  (US3 alongside US2, per dependency notes above)

---

## Parallel Example: User Story 1

```bash
# Launch all US1 test/fixture tasks together:
Task: T015 conformant corpus + runner
Task: T016 RFC master violation fixtures
Task: T017 RFC media violation fixtures
Task: T018 Apple authoring violation fixtures
Task: T019 one-shot integration tests
Task: T020 delivery-failure integration tests

# After T021 (rule engine), launch rule sets together:
Task: T022 RFC master rules
Task: T023 RFC media rules
Task: T024 Apple authoring rules
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 → Phase 2 → Phase 3 (US1)
2. **STOP and VALIDATE**: corpus tests green; quickstart scenarios 1–2 against real streams
3. MVP deliverable: CLI that validates any HLS stream one-shot with rule-referenced findings

### Incremental Delivery

1. + US2 → live troubleshooting (quickstart 3–4) — the core differentiator
2. + US3 → shareable evidence archives (quickstart 6)
3. + US4 → bandwidth audits (quickstart 5)
4. Polish → SC-005/SC-006 audit, scale test, README, full manual verification

---

## Notes

- Commit after each task or logical group (constitution workflow)
- Every Swift file: `styleguide.md` rules; every test file: `unit-testing.md` rules
- `swift build 2>&1 | xcsift` / `swift test 2>&1 | xcsift` for structured diagnostics
- Verify tests fail before implementing (Red-Green-Refactor)
- Stop at any checkpoint to validate the story independently

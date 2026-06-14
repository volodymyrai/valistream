---
description: "Task list for feature 003 — Reliable Monitoring and Evidence"
---

# Tasks: Reliable Monitoring and Evidence

**Input**: Design documents from `/specs/003-monitoring-evidence/`

**Prerequisites**: plan.md, spec.md (required); research.md, data-model.md, contracts/ (loaded)

**Tests**: Included by default (Constitution II, Test-First). Spec does **not** waive tests — quickstart.md
defines per-US automated checks. Each story's tests are written and MUST FAIL before its implementation.

**Organization**: Grouped by user story (P1→P5) for independent implementation and testing.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1–US5 (user-story phases only; Setup/Foundational/Polish carry no story label)
- Exact file paths included.

## Binding implementation rules (from plan.md → carry into every task)

- **Code style**: follow `styleguide.md` (repo root). **Tests**: follow `unit-testing.md` (repo root).
- **Skills to consult before writing the matching code**: `swift-api-design-guidelines` (new public core
  API: `EvidenceReference`/resolver, `SnapshotID`, reworked `AliasRegistry`, trace types),
  `swift-concurrency-pro` (monotonic counter under the session actor; render/event isolation; termios
  restore on cancel), `swift-testing-pro` (all test code), `swift-language` (ID grammar, slug, codec
  trim), `swift-architecture` (core/CLI boundary — termios + color stay in CLI).
- **MCP discipline (CLAUDE.md)**: **serena** for code inspection/edit/memory; **xcode-tools** for build
  (`BuildProject`, `XcodeListNavigatorIssues`, `GetBuildLog`, `XcodeRefreshCodeIssuesInFile`) and docs
  (`DocumentationSearch`). **No WebSearch.** `swift build`/`swift test` piped through `xcsift`. Bash code
  inspection needs explicit permission.
- **FROZEN — do NOT touch**: JSON report schema/field names/types/**values** (incl. `playlists[].id`);
  rule set / rule IDs / finding catalog; exit codes 0/1/2/3/130. Only permitted structured-report
  changes: pretty-print whitespace (FR-026) and artifact-index path **values** (FR-029).
- **Two distinct identifiers**: evidence joins on a finding's **`resource` URL + `refreshIndex`**, never
  on the frozen `playlists[].id`. Keep them separate.
- **Encoder discipline**: `--json` NDJSON stays **compact** `Finding.jsonEncoder` (FR-028); only files
  (report + `*.meta.json`) use the new `prettyJSONEncoder`.

## Path conventions (from plan.md)

- Core lib: `ValistreamCore/Sources/ValistreamCore/`
- Core tests: `ValistreamCore/Tests/ValistreamCoreTests/`
- CLI: `Valistream/Valistream/`
- Integration tests: `Valistream/ValistreamIntegrationTests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm a green, FROZEN-compliant baseline before any change.

- [X] T001 Establish baseline: build the workspace via xcode-tools `BuildProject` and run the full suite
      (`RunAllTests`) to confirm the FROZEN guards (`ReportJSONSchemaTests`, `RuleEngineTests`,
      conformance corpus, exit-code assertions) pass before edits — record the green baseline (SC-009).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The ID engine US1's archive naming, US2's roster/heartbeat, and US3 all build on. Isolated
here per plan (cross-cutting ID work that US1 needs).

**⚠️ CRITICAL**: No user story work begins until this phase is complete.

- [X] T002 [P] Unit tests for `SnapshotID` in `ValistreamCore/Tests/ValistreamCoreTests/SnapshotIDTests.swift`:
      `label(id:index:)` → `"<id>_<n>"`, parse helper round-trip, `_0` first fetch, VOD single-fetch.
      (FR-018a) — MUST FAIL first.
- [X] T003 Implement pure `SnapshotID` in `ValistreamCore/Sources/ValistreamCore/Session/SnapshotID.swift`:
      `label(id:index:) -> "\(id)_\(index)"` + parse helper (0-based per-playlist index). (FR-018a)
- [X] T004 [P] Unit tests for the reworked ID grammar in
      `ValistreamCore/Tests/ValistreamCoreTests/PlaylistAliasTests.swift`: `master` exact; video
      `<height>p_<codecs>` (`1080p_avc1`, `1080p_avc1-mp4a`); multi-codec fourCC trim (drop from first
      `.`) joined by `-`; slug (lowercase, non-alphanumeric runs → `_`); reserved `_` never inside a
      field value; deterministic numeric-suffix dedup; role+ordinal fallback; charset `[a-z0-9_-]`
      (filesystem-safe); determinism across runs + stability within a session. (FR-016–020, SC-006/007)
      — MUST FAIL first.
- [X] T005 Rework `AliasRegistry`/`PlaylistAlias` in
      `ValistreamCore/Sources/ValistreamCore/Session/PlaylistAlias.swift` to the new grammar — master +
      video `<height>p_<codecs>`, codec fourCC trim + `-` join, slug helper, deterministic dedup suffix,
      role+ordinal fallback. **Keep the public surface** (`alias(for:role:attributes:)` idempotent per
      URL, `all`, dedup) so call sites stay stable. Role-based audio/subtitle/I-frame forms land in US3.
      (FR-016–020)

**Checkpoint**: ID engine ready — IDs are filesystem-safe, deterministic, unique. User stories can begin.

---

## Phase 3: User Story 1 — Concrete Evidence When Something Goes Wrong (Priority: P1) 🎯 MVP

**Goal**: Every ERROR/WARN in terminal and report names the exact archived evidence file; continuity
findings name both consecutive snapshots; an uncaptured body is stated by ID (never a raw URL). Evidence
is recoverable from the frozen structured report via `resource` URL + `refreshIndex`.

**Independent Test**: Run a scripted stream producing ≥1 ERROR, ≥1 WARN, ≥1 continuity finding. Each
ERROR/WARN (terminal + report) names an evidence file that exists on disk; continuity names exactly two
consecutive snapshots; an unavailable-body finding prints `no body captured for <id>`; structured report
recovers the file(s) with no schema change.

### Tests for User Story 1 ⚠️ (write first, MUST FAIL before impl)

- [X] T006 [P] [US1] `EvidenceResolver` unit tests in
      `ValistreamCore/Tests/ValistreamCoreTests/EvidenceResolverTests.swift`: `.single` for non-continuity
      ERROR/WARN; `.pair(<id>_<n-1>, <id>_<n>)` for `category == .continuity`; `.unavailable(<id>)` when
      no body captured (placeholder `master` / role+ordinal); continuity-with-one-snapshot-missing edge;
      join on `resource` URL (never `playlists[].id`). (FR-004–009)
- [X] T007 [P] [US1] Archive-naming unit tests in
      `ValistreamCore/Tests/ValistreamCoreTests/SessionArchiveTests.swift`: `store` writes
      `playlists/<id>/<id>_<n>.m3u8` + `<id>_<n>.meta.json`; file base name equals the snapshot label;
      `IndexEntry` shape unchanged, only `bodyPath`/`metaPath` **values** change; folder/name uniqueness.
      (FR-029)
- [X] T008 [US1] Integration evidence-in-output test in
      `Valistream/ValistreamIntegrationTests/EvidenceInOutputTests.swift` (scripted in-process transport
      stub): asserts each terminal + report ERROR/WARN names an on-disk evidence file with the relevant
      content; continuity names exactly two consecutive files; unavailable-body prints `no body captured
      for <id>` with **no raw URL, no dangling path**; structured report recovers evidence via `resource`
      + `refreshIndex` with no schema change. (SC-001/002, FR-008)

### Implementation for User Story 1

- [X] T009 [US1] Add `EvidenceReference` + pure `EvidenceResolver` in
      `ValistreamCore/Sources/ValistreamCore/Session/EvidenceResolver.swift`: map `Finding` (+
      `AliasRegistry` + archive per-playlist refresh state/`artifactIndex`) → `.single` / `.pair` /
      `.unavailable`; path form `playlists/<id>/<id>_<n>.m3u8`; whole-file only; join on `resource` URL.
      (FR-004–009)
- [X] T010 [US1] Change `SessionArchive.store(result:playlistID:)` in
      `ValistreamCore/Sources/ValistreamCore/Archive/SessionArchive.swift` to name files
      `<id>_<n>.m3u8` / `<id>_<n>.meta.json` (replace `%06d`), keyed by the real presentation `<id>`;
      keep `refreshCounts`/`IndexEntry` append. (FR-029) (sidecar pretty-encoder swap is US5/T035)
- [X] T011 [US1] In `ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Reporting.swift`
      pass the **real presentation `<id>`** from the session `AliasRegistry` to `archive.store(...)`
      (replace `"master"`/`"<role>-<i>"`/`"media"` archive-ref strings). (FR-029, D6)
- [X] T012 [US1] Replace `StatusRenderer.renderFinding` in `Valistream/Valistream/StatusRenderer.swift`
      so findings print **ID + evidence** and **no** `finding.resource.absoluteString`: `ERROR/WARN
      <id>_<n> <msg> · evidence: playlists/<id>/<id>_<n>.m3u8`; continuity two paths; unavailable → `no
      body captured for <id>`. Keep the `--json` branch on the **compact** `Finding.jsonEncoder`.
      (FR-004/006/009, SC-003, FR-028)
- [X] T013 [US1] In `ValistreamCore/Sources/ValistreamCore/Session/SessionReportBuilder.swift` render
      every ERROR/WARN with the **same** evidence reference(s) as the terminal, as an **inline code span
      of the relative path only** (not a link); continuity → two spans; unavailable → `no body captured
      for <id>`. Use the shared `EvidenceResolver` for terminal/report parity. (FR-005/006/009)

**Checkpoint**: US1 fully functional and independently testable — MVP. Evidence in terminal + report,
files self-identifying, structured recovery intact.

---

## Phase 4: User Story 2 — A Clutter-Free Heartbeat You Can Read at a Glance (Priority: P2)

**Goal**: Start-of-session roster (ID → URL + role), then ID-only body (zero raw URLs at every tier),
descriptive wording, a **monotonic** session-wide heartbeat resilient to stray keystrokes, a per-refresh
status line, and a genuinely richer `--verbose` trace tier.

**Independent Test**: Long-URL session prints a roster then never repeats a full URL (normal **and**
`--verbose`); the heartbeat count is monotonic and accurate under ≥20 injected Enter presses; `--verbose`
adds ≥5 trace categories absent at normal.

### Tests for User Story 2 ⚠️ (write first, MUST FAIL before impl)

- [ ] T014 [P] [US2] Monotonic-counter unit tests in
      `ValistreamCore/Tests/ValistreamCoreTests/SessionMonotonicCounterTests.swift`: session-wide
      `sessionRefreshTotal` increments once per completed refresh across interleaved playlists; never
      decreases; equals total refreshes performed. (FR-013, SC-004)
- [ ] T015 [P] [US2] `TraceFormatter` wording tests in
      `ValistreamCore/Tests/ValistreamCoreTests/TraceFormatterTests.swift`: each `TraceEvent` variant →
      its catalog category-prefixed, **ID-based** line (fetch intent/result, per-playlist + per-rule
      validation incl. OK, stored, refresh cadence/drift, compare, rendition lifecycle); **no raw URL**.
      (FR-015b, SC-003/005)
- [ ] T016 [US2] Integration roster + zero-URL test in
      `Valistream/ValistreamIntegrationTests/RosterAndZeroURLTests.swift`: roster prints each ID → full
      URL + role **before** fetching; after the roster **no** full URL appears in the terminal body at
      normal **and** `--verbose`. (FR-011/012, SC-003)
- [ ] T017 [US2] Integration heartbeat-monotonicity-under-stray-input test in
      `Valistream/ValistreamIntegrationTests/HeartbeatMonotonicTests.swift` (ManualClock + input seam):
      inject ≥20 stray Enter presses; displayed count is monotonic non-decreasing, equals refreshes
      performed, status region uncorrupted. (FR-013/014, SC-004)
- [ ] T018 [US2] Integration verbose-vs-normal distinctness test in
      `Valistream/ValistreamIntegrationTests/VerboseDistinctnessTests.swift`: `--verbose` line-set adds
      ≥5 categories absent at normal; all verbose lines ID-based. (FR-015, SC-005)

### Implementation for User Story 2

- [ ] T019 [US2] Extend `SessionEvent` + `ActivityProgress` in
      `ValistreamCore/Sources/ValistreamCore/Session/SessionConfig.swift` with **additive** cases
      `.rosterReady([RosterEntry])`, `.refreshCompleted(playlistID:index:errors:warnings:)`,
      `.trace(TraceEvent)`, plus `ActivityProgress.sessionRefreshTotal: Int` (+ `RosterEntry`,
      `TraceEvent` types). No JSON/exit impact. (FR-011/013/015a/b, D7/D9)
- [ ] T020 [US2] Maintain the session-wide monotonic refresh counter under the session actor in
      `ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift`: increment once
      per completed refresh across all playlists; carry it in the activity event. (FR-013, SC-004, D7)
- [ ] T021 [US2] Emit `.rosterReady`, `.refreshCompleted`, and verbose `.trace` events from
      `ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Reporting.swift` at the right
      points (roster before fetch; per-refresh roll-up; fetch/validate/store/refresh/compare/lifecycle
      traces). (FR-011/015b)
- [ ] T022 [P] [US2] Add pure `TraceFormatter` in
      `ValistreamCore/Sources/ValistreamCore/Output/TraceFormatter.swift`: render each `TraceEvent` to a
      category-prefixed, ID-based line per the catalog. (FR-015b)
- [ ] T023 [US2] Update heartbeat wording in
      `ValistreamCore/Sources/ValistreamCore/Output/ProgressFormatter.swift` to
      `<id> · refresh <sessionRefreshTotal> · <elapsed>` and descriptive, ID-based action wording.
      (FR-010/013)
- [ ] T024 [US2] Update `Valistream/Valistream/ProgressView.swift` to display the monotonic
      `sessionRefreshTotal` + current ID in the in-place region. (FR-013)
- [ ] T025 [US2] Add CLI-only `Valistream/Valistream/LiveInputGuard.swift`: on TTY + live monitoring,
      clear `ECHO`/`ICANON` via `termios` on entry and **restore** original termios on every exit path
      (normal, time-limit, graceful stop, force-quit) via `defer`; gated on TTY so piped runs emit no
      control bytes. Reuses the `PlaylistChecklist` termios pattern. (FR-014, SC-004, D8)
- [ ] T026 [US2] Wire roster, per-refresh status line, and verbose trace gating into
      `Valistream/Valistream/StatusRenderer.swift`: render `.rosterReady` (normal+), `.refreshCompleted`
      as `<id>_<n> — OK` / `<id>_<n> — x WARN, y ERROR` with findings indented beneath, and `.trace`
      only at `--verbose`; enforce tier supersets (quiet ⊆ normal ⊆ verbose). Keep `--json` compact.
      (FR-012/015a/b, SC-003)

**Checkpoint**: US1 + US2 both work independently. Calm, ID-based, rock-steady heartbeat; rich verbose.

---

## Phase 5: User Story 3 — Meaningful, Differentiated Playlist IDs (Priority: P3)

**Goal**: Role-based audio/subtitle/I-frame IDs complete the scheme; the report legend maps every ID →
URL + role; IDs are demonstrably differentiated, deterministic, and stable end-to-end. (Master + video
grammar landed in Foundational.)

**Independent Test**: Run against a master with several video renditions differing by resolution/codec
plus audio/subtitle/I-frame. Master ID is `master`; each video ID is `<height>p_<codecs>` and distinct;
audio/subtitle/I-frame get clear role IDs (`audio_en`, `audio_en_commentary`, `subs_en`, `iframe_720p`);
re-run yields identical IDs.

### Tests for User Story 3 ⚠️ (write first, MUST FAIL before impl)

- [ ] T027 [P] [US3] Role-based ID unit tests in
      `ValistreamCore/Tests/ValistreamCoreTests/PlaylistAliasRoleTests.swift`: `audio_<slug(LANGUAGE)>`;
      same-language collision appends `_<slug(NAME)>` (`audio_en_commentary`); `NAME` alone when
      `LANGUAGE` absent; `subs_<slug(LANGUAGE|NAME)>`; `iframe_<height>p`; role+ordinal fallback when
      attributes missing. (FR-018/020, SC-006)
- [ ] T028 [US3] Integration ID-differentiation/determinism test in
      `Valistream/ValistreamIntegrationTests/PlaylistIDSchemeTests.swift`: master=`master`; video IDs
      `<height>p_<codecs>` distinct for codec-only and resolution-only differences; role IDs distinct;
      re-run identical; ID stable across refreshes; legend present in the report. (SC-006/007)

### Implementation for User Story 3

- [ ] T029 [US3] Add role-based audio/subtitle/I-frame derivation to
      `ValistreamCore/Sources/ValistreamCore/Session/PlaylistAlias.swift`: `audio_<slug(LANGUAGE)>` with
      `NAME` disambiguation, `subs_<…>`, `iframe_<height>p`, role+ordinal fallback — same dedup/charset
      guarantees as the Foundational rework. (FR-018/020)
- [ ] T030 [US3] Render the report **legend** (each ID → full URL + role/attributes) in the new ID
      scheme in `ValistreamCore/Sources/ValistreamCore/Session/SessionReportBuilder.swift`; legend is the
      only place URLs appear in the report. (FR-012, SC-003)

**Checkpoint**: All IDs meaningful, differentiated, deterministic, and consistently used.

---

## Phase 6: User Story 4 — Process Everything by Default, Prompt Only on Request (Priority: P4)

**Goal**: All renditions processed by default with no prompt (even on a TTY); `--all` removed;
`--preselect <pattern>` for unattended subset; `--select` raises the interactive checklist; mutual
exclusion and non-TTY fallback handled; version 0.3.0 with breaking-change migration docs.

**Independent Test**: No flags → all processed, no prompt (TTY too); `--all` → exit 2; `--preselect
<pattern>` → subset, no prompt; `--select` on TTY → pre-selected checklist; `--select`+`--preselect` →
exit 2; `--select` non-TTY → all + notice.

### Tests for User Story 4 ⚠️ (write first, MUST FAIL before impl)

- [ ] T031 [P] [US4] `SelectionPromptPolicy` unit tests in
      `ValistreamCore/Tests/ValistreamCoreTests/SelectionPromptPolicyTests.swift`: prompt iff `--select`
      + TTY; default (no flags) → no prompt even on TTY; `--preselect` → no prompt; `--select` +
      `--preselect` → usage error; `--select` non-TTY → fallback-to-all. (FR-021–025)
- [ ] T032 [US4] Integration selection-matrix test in
      `Valistream/ValistreamIntegrationTests/SelectionMatrixTests.swift`: prompt closure NOT called for
      default/`--preselect`; pattern filter applied; `--all` → exit 2; `--select`+`--preselect` → exit 2;
      `--select` non-TTY → all + notice. (SC-010)

### Implementation for User Story 4

- [ ] T033 [US4] Update selection flags in `Valistream/Valistream/ValistreamCommand.swift`: remove the
      `--all` `@Flag` (now unknown → exit 2); add `--preselect <pattern>` `@Option` feeding
      `SessionConfig.selectionPatterns`; repurpose `--select` to a `@Flag` (interactive checklist,
      all pre-selected); `--select`+`--preselect` → usage error exit 2; `--select` non-TTY → fall back to
      all and print the documented notice. (FR-021–025)
- [ ] T034 [US4] Rewire `SelectionPromptPolicy.from(...)` (in `ValistreamCore/Sources/ValistreamCore/Session/SelectionPromptPolicy.swift`) to key prompting off
      the new `--select` flag + mutual exclusion (replacing the 002 pattern/`--all` rule) so the prompt
      appears **only** for `--select` on a TTY. (FR-021/024, D11)
- [ ] T035 [US4] Set `MARKETING_VERSION = 0.3.0` in `Valistream/Valistream.xcodeproj` and update
      `--version`/`--help` to document **every** option, calling the selection changes out as **breaking**
      with the migration mapping (`--all`→default; `--select <pattern>`→`--preselect`; `--select`→
      interactive checklist). (FR-003, D12)

**Checkpoint**: Default-all selection model live; breaking change documented; version 0.3.0.

---

## Phase 7: User Story 5 — Readable, Pretty-Printed JSON Artifacts (Priority: P5)

**Goal**: Every JSON **file** on disk is pretty-printed with stable key ordering; the `--json` status
stream stays one compact object per line.

**Independent Test**: Open the structured report and a `*.meta.json` sidecar — both multi-line/indented
and parse to the same content; report still validates the frozen schema; captured `--json` is exactly one
compact object per line.

### Tests for User Story 5 ⚠️ (write first, MUST FAIL before impl)

- [ ] T036 [P] [US5] Pretty/compact encoder unit tests in
      `ValistreamCore/Tests/ValistreamCoreTests/JSONEncoderTests.swift`: `prettyJSONEncoder` →
      multi-line, `.sortedKeys` stable ordering, schema-valid; `jsonEncoder` (stream) stays
      compact/single-line; both decode to identical logical content. (FR-026/027/028, SC-008)
- [ ] T037 [US5] Integration pretty-JSON test in
      `Valistream/ValistreamIntegrationTests/PrettyJSONFilesTests.swift`: structured report + sidecar on
      disk are multi-line/indented and schema-valid; `--json` stream remains one compact object per line.
      (SC-008/009)

### Implementation for User Story 5

- [ ] T038 [US5] Add `Finding.prettyJSONEncoder` (`[.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]`,
      ISO-8601) in `ValistreamCore/Sources/ValistreamCore/Validation/Finding.swift`; **keep** the compact
      `Finding.jsonEncoder` for the `--json` stream. (FR-026/028, D10)
- [ ] T039 [US5] Use `prettyJSONEncoder` in `buildJSON` of
      `ValistreamCore/Sources/ValistreamCore/Session/SessionReportBuilder.swift` for the structured
      report file; values FROZEN — whitespace only. (FR-026/027)
- [ ] T040 [US5] Use `prettyJSONEncoder` for the `*.meta.json` sidecar in
      `ValistreamCore/Sources/ValistreamCore/Archive/SessionArchive.swift` (depends on T010 naming).
      (FR-026)

**Checkpoint**: All on-disk JSON pretty; `--json` stream unchanged.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T041 Run all of `quickstart.md` (US1–US5 automated checks) via xcode-tools `RunAllTests`;
      confirm green.
- [ ] T042 Re-confirm the FROZEN guards (`ReportJSONSchemaTests`, `RuleEngineTests`, conformance corpus,
      exit-code assertions) show zero regression vs the T001 baseline. (SC-009)
- [ ] T043 [P] Style/test compliance pass over all new/changed files against `styleguide.md` and
      `unit-testing.md`; resolve `XcodeListNavigatorIssues` warnings.
- [ ] T044 Update serena memory (`implementation-progress`) with the 003 outcome, new public core API
      (`EvidenceReference`/resolver, `SnapshotID`, reworked `AliasRegistry`, `TraceEvent`/`TraceFormatter`),
      and the archive-naming + encoder changes.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (P1)**: none.
- **Foundational (P2)**: after Setup — **BLOCKS all user stories** (ID engine).
- **User stories (P3–P7)**: all depend on Foundational. Then orderable by priority US1→US5, or in
  parallel where files don't overlap (see below).
- **Polish (P8)**: after all targeted stories.

### Story dependencies & shared-file notes

- **US1 (P1)**: after Foundational. MVP. No dependency on other stories.
- **US2 (P2)**: after Foundational. Touches `StatusRenderer.swift` (also US1/T012),
  `SessionReportBuilder.swift` (also US1/T013, US3/T030), `SessionConfig.swift` — sequence shared-file
  edits after US1's.
- **US3 (P3)**: after Foundational; extends `PlaylistAlias.swift` (Foundational/T005) and
  `SessionReportBuilder.swift` (legend — coordinate with T013/T030).
- **US4 (P4)**: after Foundational. Mostly independent CLI files; can run in parallel with US1–US3.
- **US5 (P5)**: after Foundational. `SessionArchive.swift` sidecar (T040) depends on US1/T010 naming;
  `SessionReportBuilder.swift` `buildJSON` (T039) coordinate with US1/US3 edits.

### Within each story

- Tests written first and MUST FAIL before implementation.
- Core types/engine before consumers; emit events before render; render before integration assertions.

### Parallel opportunities

- Foundational: T002 ∥ T004 (different test files); impl T003 then T005.
- US1 tests: T006 ∥ T007 (different files) before T008.
- US2 tests: T014 ∥ T015; `TraceFormatter` impl T022 parallel to counter/render work on other files.
- US4 is largely parallel to US1–US3 (separate CLI/policy files).
- Across stories: with capacity, US4 (CLI) can proceed alongside US1–US3 (core/render) once Foundational
  is done.

---

## Parallel Example: User Story 1

```text
# Tests first (different files, in parallel):
Task: "EvidenceResolver unit tests in ValistreamCore/Tests/ValistreamCoreTests/EvidenceResolverTests.swift"  (T006)
Task: "Archive-naming unit tests in ValistreamCore/Tests/ValistreamCoreTests/SessionArchiveTests.swift"      (T007)

# Then implementation (resolver and archive are different files → parallelizable):
Task: "EvidenceReference + EvidenceResolver in .../Session/EvidenceResolver.swift"  (T009)
Task: "Snapshot naming in .../Archive/SessionArchive.swift"                          (T010)
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational (ID engine) → 3. Phase 3 US1 → **STOP & VALIDATE** evidence
   end-to-end (terminal + report + structured recovery) → demo. This alone is the highest-value win.

### Incremental delivery

Setup + Foundational → US1 (MVP, evidence) → US2 (heartbeat/roster/verbose) → US3 (role IDs + legend) →
US4 (selection + version) → US5 (pretty JSON). Each ships independently without breaking the prior.

### Parallel team strategy

After Foundational: Dev A → US1 (core evidence + render), Dev B → US2 (events/heartbeat/trace), Dev C →
US4 (CLI selection + version). US3 and US5 fold in after US1's shared-file edits land.

---

## Notes

- [P] = different files, no dependency on incomplete tasks.
- FROZEN: JSON schema/values (incl. `playlists[].id`), rule set/IDs/catalog, exit codes — never edited.
- Evidence joins on `resource` URL + `refreshIndex`, never `playlists[].id`.
- `--json` stream stays compact; only files pretty-print.
- Verify each story's tests FAIL before implementing; commit after each task or logical group.

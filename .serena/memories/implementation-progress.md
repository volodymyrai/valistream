# Valistream implementation progress

See `mem:implementation-setup` for layout, build/test commands (xcode-tools), test plans/schemes, serena-LSP-unavailable caveat.

## Test restructure (June 2026) — DONE
Integration tests moved OUT of the SwiftPM package INTO the CLI Xcode project:
- `ValistreamIntegrationTests` testTarget removed from `Package.swift` (package = `ValistreamCore` library + `ValistreamCoreTests` ONLY now — 1 test target, not 2).
- Integration sources + test stubs in `Valistream/Valistream/ValistreamIntegrationTests/` (incl. `Support/ScriptedStreamFetcher.swift`, `Support/ManualClock.swift`); unit-test-bundle target in `Valistream.xcodeproj`.
- Test plans: `ValistreamCore.xctestplan` (unit; package scheme) + `Valistream.xctestplan` (unit + integration; CLI scheme). `swift test` in package runs unit/conformance only; integration runs via Xcode `Valistream` scheme (xcode-tools RunSomeTests/RunAllTests, tab windowtab1).

## CLI restructure (June 2026) — DONE
CLI split into Xcode project tool target `Valistream` (sources `Valistream/Valistream/Valistream/`), links `ValistreamCore` (local) + `ArgumentParser` (remote). SWIFT_VERSION 6.0.

## Done (features)
- **Phase 1 (T001-T003)**: package skeleton, build green.
- **Phase 2 Foundational (T004-T015)**: tokenizer+AttributeList, playlist model+builder, Finding, StreamFetching/FetchResult/ArtifactRecord, URLSessionStreamFetcher, ScriptedStreamFetcher + ManualClock, SessionState+SessionLifecycle, ValidationSession actor, RuleEngine.
- **Phase 3 US1 MVP (T016-T028)**: RFC8216 master+media rules, AppleAuthoringRules, StreamClassifier, PlaylistLoader, ValidationSession.run() one-shot, CLI (ValistreamCommand + StatusRenderer, exit 0/1/2/3).
- **Phase 4 US2 live monitoring (T029-T040) — DONE (June 2026)**:
  - Pure components in `Sources/ValistreamCore/Monitoring/`: `RefreshScheduler` (RFC 8216 §6.3.4: initialDelay=TD, nextDelay changed=TD / unchanged=TD/2), `ContinuityChecker` (media-seq regression, head-removal, segment-stability mutation, discontinuity-inserted INFO, discontinuity-seq regression), `StalenessDetector` (>1.5×TD warning, >3×TD error, strict `>`), `Duration+Seconds.swift` (internal `.seconds` Double), `MonitorState` enum.
  - `Session/PlaylistSelection.swift`: `PlaylistSelection.Candidate` + `resolve(_:patterns:)` (nil/empty patterns → all; else localizedStandardContains match on id/groupID/name/url).
  - `ValidationSession` extended: added `sleep` closure param (default Task.sleep) + `selectPlaylists` provider closure param; `monitor()` via `withDiscardingTaskGroup`, `monitorPlaylist()` reload loop (sleep→fetch→re-validate `recordIfNew` dedup by signature→continuity→staleness→monitorState), `abort()`→aborted / `requestStop()`, time-limit deadline via now(), empty-selection note `TOOL.selection-empty`. New `SessionEvent.monitorStateChanged`.
  - CLI (T040): StatusRenderer handles monitorStateChanged + `--json` status objects to stdout; SIGINT/SIGTERM via DispatchSource → `abort()` + cancel runTask → exit 130 (state==.aborted); `--all` wiring; `PlaylistChecklist.swift` termios checkbox + numbered fallback + select-all when no TTY.
  - Tests: unit RefreshSchedulerTests/ContinuityCheckerTests/StalenessDetectorTests (Monitoring/), PlaylistSelectionTests (Session/). Integration `LiveMonitoringTests` + `LiveFaultScenarioTests` (+ Support `LiveSessionHarness` driving ManualClock deterministically via sleeperCount, `LivePlaylists` builder; added `sleeperCount`/`elapsedSeconds` to ManualClock).
- **125 unit tests green** (`swift test`); **140 total tests green** via Xcode (Valistream.xctestplan) — includes 5 new InterruptedSessionTests integration tests.

## New rule IDs (US2)
TOOL.continuity.media-sequence, .head-removal, .segment-stability, .discontinuity-inserted (info), .discontinuity-sequence; TOOL.staleness; TOOL.selection-empty (info).

## Rule IDs (US1, fixture/report consistency)
RFC8216.4.3.1.1, .4.3.4.2-BANDWIDTH, .4.3.4.2-URI, .4.3.4.1, .4.3.4.2.1, .4.3.3.1, .4.3.3.1-DURATION, .4.3.2.1, .4.3.3-DUPLICATE; APPLE.codecs/.average-bandwidth/.resolution/.independent-segments/.iframe-playlists/.variant-ladder/.target-duration; TOOL.delivery/.low-latency/.encryption.

## US3 done (June 2026) — T041-T050 all [X]
- `SessionArchive` actor: session folder `<outputDir>/<sessionID>/`, per-playlist `playlists/<id>/NNNNNN.m3u8` + `.meta.json` sidecars, `artifactIndex` accumulates across stores.
- `FindingsLog` (@unchecked Sendable class, JSONL append-only, `0x0A` per entry — durable on abort).
- `DiskSpaceWatcher` struct, injected capacity provider, warn ≤5 GiB / stop ≤500 MiB.
- `SessionReportBuilder`: `buildJSON` (schema v1, schemaVersion/session/stream/playlists/findings/summary/artifactIndex) + `buildMarkdown`.
- `ValidationSession` wired: archive/log/watcher created when `config.archiveEnabled`; every fetch archived (master as "master", media refs as "\(role)-\(i)", direct media as "media"); `record()` appends to JSONL; `setState(.aborted)` called BEFORE `writeReport` (bug fix — snapshot captures correct state); `finish()` async writes report.
- `SessionConfig.archiveEnabled` defaults `false` — existing tests unaffected.
- CLI sets `archiveEnabled: true`, prints `sessionFolderURL` path.
- New unit tests: SessionArchiveTests (8), FindingsLogTests (5), DiskSpaceWatcherTests (10), SessionReportTests (12).
- New integration tests: InterruptedSessionTests (5) — all with `.timeLimit(.minutes(1))`.
- File was placed in wrong dir (one level up); fixed by moving to `Valistream/Valistream/ValistreamIntegrationTests/`.
- `SessionConfig` param order: `outputDir` precedes `nonInteractive` — must match in all call sites.

## US4 alias phase done (June 2026) — T030–T039 all [X]
- `PlaylistAlias` + `AliasRegistry` in `Session/PlaylistAlias.swift`: deterministic stable aliases (`video-1080p`/`audio-en`/`subs-fr`/`iframe-720p`), indexed fallback (`V1`/`A1`/`S1`/`I1`/`M1`), dedup suffix (`video-1080p-2`).
- `AliasRole` enum + `AliasRole(from: PlaylistRole)` bridge.
- `SessionArchive.writeAtomically(_:to:)` `nonisolated` — temp-file + `FileManager.replaceItemAt` (FR-022).
- `SessionReportBuilder.buildMarkdown` rewritten: header table / Summary / Legend / Findings (grouped severity→category, aliases only, no raw .m3u8 in body) / Per-playlist; `aliasRegistry: AliasRegistry = AliasRegistry()` default param preserves existing call sites.
- `ValidationSession.swift` split to <500 lines: `ValidationSession+Monitoring.swift` (monitor/monitorPlaylist/evaluateStructural/evaluateStaleness) + `ValidationSession+Reporting.swift` (archiveFetch/writeReport). Internal (not private) access on shared properties for extensions.
- Per-cycle atomic writes: `writeReport(interruption:)` called at end of each refresh loop in `monitorPlaylist()`.
- Alias registration at discovery in `run()` via `makeAttributes(for:in:)` helper; `aliasInScope` threaded into `.activity` events.
- **233 tests green** (RunAllTests, Xcode Valistream scheme).

## US5 done (June 2026) — T040–T048 all [X]
- `SelectionPromptPolicy` enum in `Session/SelectionPromptPolicy.swift`: `.prompt`/`.skip` with `from(isTTY:nonInteractive:selectionPatterns:)` factory — encodes FR-028 skip rule.
- `PromptberrySelection` in `Valistream/PromptberrySelection.swift`: wraps `Promptberry.multiselect`, all candidates pre-selected, `SelectOption<String>` (ID-based) map. On `PromptCancelled` → `Promptberry.cancel` + `Foundation.exit(0)` (FR-029).
- `ValistreamCommand` updated: `SelectionPromptPolicy.from(isTTY:nonInteractive:all:selectionPatterns:)` drives `selectPlaylists` nil-or-closure; `--select` now also skips prompt (was a bug). `--segments`/`--tolerance` hidden (`.hidden`).
- `ProgressView.render` truncates in-place TTY line to terminal width via `ioctl TIOCGWINSZ` (T045, narrow-terminal edge case).
- `README.md` created at repo root documenting all options, exit codes, and session output (T046).
- Unit: 7 new `SelectionPromptPolicyTests` in `Session/` — all skip conditions + default-selection behavior. `swift test`: **189 tests green**.
- Integration: 3 new `PromptSkipTests` — prompt-closure not called, pattern filter applied, all playlists fetched. Xcode RunAllTests: **37 tests green**.

## US4 selection-flag rework done (June 2026) — T031–T035 all [X]
- `SelectionPromptPolicy` REWRITTEN: new cases `.prompt`/`.skip`/`.usageError`; new factory `from(isTTY:selectFlag:preselectPatterns:)` replacing `from(isTTY:nonInteractive:selectionPatterns:)`. Mutual exclusion now returns `.usageError` instead of requiring caller to detect.
- `ValistreamCommand.swift` updated: `--all` @Flag REMOVED (now ArgumentParser rejects it as unknown option, exits 64/EX_USAGE on macOS); `--select` repurposed from `@Option String?` to `@Flag Bool` (interactive checklist request); `--preselect` `@Option String?` added (former `--select <pattern>` role); `--select`+`--preselect` → exit 2 with message; `--select` non-TTY → exit-2 not thrown, notice printed to stderr + all processed; `nonInteractive` no longer set from `all` flag.
- `CommandConfiguration.version` bumped to `"0.3.0"`; `discussion` added with breaking-change migration table.
- `MARKETING_VERSION = 0.3.0` in all configs in `Valistream.xcodeproj/project.pbxproj`.
- `SelectionPromptPolicyTests.swift` fully rewritten to test new API + `.usageError` case.
- New `SelectionMatrixTests.swift` in `ValistreamIntegrationTests/`: 8 tests (5 policy-seam + 3 session-level) — all green.
- **230 unit tests green** (`swift test`); **8 SelectionMatrixTests + 3 PromptSkipTests green** (Xcode).
- Exit-code limitation: `--all` exits 64 (ArgumentParser `EX_USAGE`) not 2 — this is ArgumentParser's macOS behavior for unknown options; spec text said "exit 2" meaning "usage error class", not the literal code 2.

## NOT done (remaining)
- T036–T044: US5 pretty-JSON + polish (next worker).
- T049: Manual quickstart against real streams (cannot run headless). FR-029 manual Ctrl-C prompt cancel test.

## Deviations / notes
- swift-tools-version 6.3 (template), not 6.0 as T001 text says.
- Finding JSON uses .withoutEscapingSlashes.
- Fixtures are Swift string constants; corpus/violation tests in Tests/ValistreamCoreTests/Conformance/.
- No git commit made (awaiting user request).
- Manual quickstart against real streams (T028/T060) not run. PlaylistChecklist termios path build-verified but not runtime-tested (headless env).
- Monitoring elapsed/staleness measured via injected `now` (Date); tests pin `now` to ManualClock offset so now()+sleep stay consistent.
- RunAllTests was flaky/cancelled twice in this env; RunSomeTests subsets reliable.

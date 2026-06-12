# Valistream implementation progress

See `mem:implementation-setup` for layout, build/test commands (xcode-tools tab `windowtab1`), serena-LSP-unavailable caveat.

## Restructure (June 2026) — DONE
CLI split out of the SwiftPM package into the Xcode project:
- `valistream` executable target + `.executable` product + `swift-argument-parser` dependency removed from `Package.swift` (package = `ValistreamCore` library + 2 test targets only).
- CLI sources moved `Package/Sources/valistream/` -> `Valistream/Valistream/Valistream/` (sync group); placeholder `main.swift` deleted (`@main` conflict).
- `Valistream.xcodeproj` tool target now links `ValistreamCore` (local pkg) + `ArgumentParser` (remote pkg); SWIFT_VERSION 5.0->6.0.
- BuildProject green; CLI runs (`--version` 0.1.0, `--help`, bad URL -> exit 2). Supporting docs updated: CLAUDE.md, plan.md, quickstart.md, tasks.md.

## Done (features)
- **Phase 1 (T001-T003)**: 4-target package (orig), skeleton, build green.
- **Phase 2 Foundational (T004-T015)**: tokenizer+AttributeList, playlist model+builder, Finding (Codable, matches session-report.schema.json), StreamFetching/FetchResult/ArtifactRecord, URLSessionStreamFetcher (OSAllocatedUnfairLock delegate), ScriptedStreamFetcher + ManualClock (test support), SessionState+SessionLifecycle, ValidationSession actor, RuleEngine.
- **Phase 3 US1 MVP (T016-T028)**: RFC8216 master rules, RFC8216 media rules, AppleAuthoringRules, StreamClassifier (vod/event/live + LL-HLS/encryption info), PlaylistLoader (delivery findings), ValidationSession.run() one-shot flow, CLI (ValistreamCommand + StatusRenderer, exit codes 0/1/2/3).
- **66 tests green** (last confirmed before restructure).

## Rule IDs implemented (fixture/report consistency)
- RFC8216.4.3.1.1 (EXTM3U first), .4.3.4.2-BANDWIDTH, .4.3.4.2-URI (dangling stream-inf), .4.3.4.1 (EXT-X-MEDIA required attrs), .4.3.4.2.1 (group ref)
- RFC8216.4.3.3.1 (targetduration), .4.3.3.1-DURATION (segment>target), .4.3.2.1 (missing EXTINF), .4.3.3-DUPLICATE
- APPLE.codecs/.average-bandwidth/.resolution/.independent-segments/.iframe-playlists/.variant-ladder/.target-duration
- TOOL.delivery, TOOL.low-latency, TOOL.encryption

## NOT done (remaining)
- US2 (T029-T040): live monitoring — RefreshScheduler, ContinuityChecker, StalenessDetector, monitoring TaskGroup wiring, PlaylistSelection + interactive checklist (termios), CLI live status + SIGINT->130 + --json. NOTE T040 PlaylistChecklist + any CLI task now lives in `Valistream/Valistream/Valistream/` (Xcode target), not the package.
- US3 (T041-T050): SessionArchive, FindingsLog (JSONL), DiskSpaceWatcher, SessionReportBuilder. ValidationSession does NOT archive yet; --output-dir accepted but unused.
- US4 (T051-T055): SegmentAuditor + wiring + CLI flags.
- Polish (T056-T060).

## Deviations / notes
- swift-tools-version 6.3 (template), not 6.0 as T001 text says.
- Finding JSON uses .withoutEscapingSlashes (clean URLs).
- Fixtures are Swift string constants (not .m3u8 resource files); corpus/violation tests in Tests/ValistreamCoreTests/Conformance/.
- No git commit made (awaiting user request).
- Manual quickstart against real streams (T028/T060) not run.

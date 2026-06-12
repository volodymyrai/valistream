# Implementation Plan: HLS Stream Validator

**Branch**: `main` (no feature branch — git extension not installed) | **Date**: 2026-06-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-hls-stream-validator/spec.md`

## Summary

A command-line HLS stream validator: given a master playlist URL it validates the master and all
referenced media playlists against RFC 8216 plus playlist-observable Apple HLS Authoring
Specification rules; for live streams it monitors selected playlists at player-accurate refresh
cadence and validates inter-refresh continuity; optionally downloads segments to audit declared
bandwidth; every fetched resource is archived per session with full request/response metadata.

Technical approach: a Swift 6 SwiftPM package with a core library (custom line-level M3U8 parser,
rule-based validation engine, actor-based live monitoring scheduler, artifact archive writer) and a
thin CLI executable. Networking via URLSession with `URLSessionTaskMetrics` for remote IP and timing
capture. Tests use Swift Testing with a fixture corpus of conformant/violating playlists and
scripted in-process transport stubs for integration scenarios (no local server).

## Technical Context

**Language/Version**: Swift 6.x (strict concurrency), Swift Package Manager

**Primary Dependencies**: Foundation/URLSession (networking), swift-argument-parser (CLI parsing —
only external dependency)

**Storage**: Local filesystem — one folder per session (artifacts verbatim + JSON metadata sidecars,
JSON + Markdown session reports). No database.

**Testing**: Swift Testing (`swift test`); unit tests against fixture playlist corpus; integration
tests drive the session engine through a scripted `StreamFetching` stub simulating VOD/live/faulty
streams in-process (no sockets); test development follows repository `unit-testing.md` (mandatory)

**Target Platform**: macOS 14+ (CLI). Linux portability kept plausible (no AppKit; FoundationNetworking
caveats documented in research.md) but not a v1 requirement.

**Project Type**: Single SwiftPM package: 1 library target (core) + 1 executable target (CLI) + test
targets

**Performance Goals**: Full one-shot validation of a 20-playlist stream < 30 s on responsive network
(SC-001); 24 h live session with ≥ 99% of refreshes on cadence (SC-003); refresh scheduling accuracy
within ±10% of target-duration-derived interval

**Constraints**: No media decoding/decryption (FR-013); memory bounded for 24 h sessions (stream
artifacts to disk, don't accumulate in memory); every network request archived (SC-004); polite
client behavior — request cadence mirrors RFC 8216 §6.3.4, no hammering

**Scale/Scope**: Masters with up to ~50 media playlists; sessions producing hundreds of thousands of
small files (~1–2 GB/24 h); single stream per process invocation

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Spec-First | Approved spec with resolved clarifications exists before this plan | ✅ spec.md complete, 7 clarifications recorded, checklist 16/16 |
| II. Test-First | Plan provides test strategy; tasks will generate test-first tasks per story | ✅ fixture corpus + scripted-transport integration tests defined (research.md §8); tests default-on |
| III. Simplicity | No unjustified projects/abstractions/dependencies | ✅ one library package + one thin CLI tool target; single external dependency (swift-argument-parser) justified; custom parser justified (core domain, line-level fidelity required) — see research.md §2, §6 |
| IV. Independent Increments | Story slices independently implementable/testable | ✅ P1 one-shot validation → P2 live monitoring → P3 archive → P4 segments; each lands as runnable CLI increment |
| V. Observability & Versioning | Structured output; semver | ✅ findings are structured (JSON report schema, contracts/); CLI exit codes contract; package semver from 0.1.0 |

**Initial evaluation**: PASS (no violations; Complexity Tracking empty).

**Post-design re-evaluation**: PASS — design artifacts introduce no new projects or dependencies
beyond those justified above.

## Project Structure

### Documentation (this feature)

```text
specs/001-hls-stream-validator/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── cli-interface.md
│   └── session-report.schema.json
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code

The CLI was split out of the SwiftPM package into an Xcode project under a shared workspace:

```text
Valistream/
├── Valistream.xcworkspace              # ties the project + package together
├── Valistream/
│   └── Valistream.xcodeproj            # CLI tool target "Valistream"
│       └── Valistream/                 # CLI sources: argument parsing, status rendering, exit codes
└── Package/                            # SwiftPM package (library + tests)
    ├── Package.swift
    ├── Sources/
    │   └── ValistreamCore/             # library target: all domain logic, UI-free
    │       ├── Playlist/               # M3U8 line-level parser + playlist model (master/media)
    │       ├── Validation/             # rule engine; RFC8216 + AppleAuthoring rule sets; Finding model
    │       ├── Monitoring/             # live refresh scheduler, continuity checker, staleness detection
    │       ├── Networking/             # HTTP client wrapper, URLSessionTaskMetrics capture, redirects
    │       ├── Archive/                # session folder layout, artifact + metadata writer, disk watcher
    │       ├── Segments/               # opt-in segment download + bandwidth audit
    │       └── Session/                # ValidationSession orchestrator (actor), session report builder
    └── Tests/
        ├── ValistreamCoreTests/        # Swift Testing; unit tests per module (+ Fixtures/ corpus)
        └── ValistreamIntegrationTests/ # end-to-end: scripted StreamFetching stub timelines
```

**Structure Decision**: One SwiftPM package exposing the `ValistreamCore` library, plus a thin CLI
tool in an Xcode project, joined by a workspace. `ValistreamCore` holds every behavior the spec
defines (parse → validate → monitor → archive → report) so it is fully testable without a terminal;
the `Valistream` CLI target is a thin presentation/IO shell that links `ValistreamCore` +
`ArgumentParser`. This keeps the core fully reusable and a future GUI wrapper possible without core
changes (Clarification #2).

## Implementation Guidance

Binding instructions for the implementation phase (`/speckit-tasks` must surface these; the
implementing agent must follow them):

- **Code style**: MUST follow the repository style guide — [`styleguide.md`](../../styleguide.md)
  (repo root).
- **Test development**: MUST follow [`unit-testing.md`](../../unit-testing.md) (repo root) for all
  test code, in addition to the strategy in research.md §8.
- **Skills to consult while implementing** (read before writing the corresponding code):
  `swift-testing-pro` (test code), `swift-concurrency-pro` (actors/TaskGroup/AsyncStream work),
  `swift-api-design-guidelines` (public API naming in ValistreamCore), `swift-architecture`
  (module/layer decisions), `swift-language` (core Swift idioms).
- **Build/test log analysis**: use `xcsift` — pipe `swift build` / `swift test` output through it
  for structured errors, warnings, and test failures.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

(No violations — table intentionally empty.)

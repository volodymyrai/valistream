# Implementation Plan: Performance and UX

**Branch**: `main` (no feature branch — git extension not installed) | **Date**: 2026-06-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-performance-ux/spec.md`

## Summary

Make the existing HLS Stream Validator (feature 001) dramatically more usable **without changing any
validation behavior, the structured-report schema, or the exit-code contract** (FR-003). The work is:
keep the interface continuously responsive while narrating live activity + progress (US1); a unified,
bounded graceful stop for any session (US2); user-controlled, pre-flighted output locations (US3); a
live-updating, atomically-written, prettified human report that refers to playlists by stable aliases
with a resolving legend (US4); and a polished interactive selection prompt (US5).

Technical approach: the domain core (`ValistreamCore`) stays a **pure, zero-external-dependency**
library — it gains only pure logic (playlist **aliases**, an **output-location** resolver, richer
**progress/activity events** on the existing `events` stream, per-refresh-cycle **atomic** report
writes, and a **unified finalization** path for completion / graceful stop / time limit). All new
*presentation* concerns live in the thin CLI target, which adopts **Rainbow** (color) and
**Promptberry** (interactive prompts) as remote SwiftPM dependencies attached to the CLI target only.
The executable is renamed to `valistream` via `PRODUCT_NAME`. Decisions are recorded in
[research.md](research.md); entities in [data-model.md](data-model.md); behavior in
[contracts/](contracts/).

## Technical Context

**Language/Version**: Swift 6.x (strict concurrency), Swift Package Manager + Xcode workspace
(`Valistream.xcworkspace`) — unchanged from feature 001.

**Primary Dependencies**:
- *Core* (`ValistreamCore`): Foundation only — **zero external dependencies** (unchanged).
- *CLI target* (`Valistream`): `swift-argument-parser` (existing) **+ new: Rainbow** (terminal color)
  **and Promptberry** (interactive prompts), attached to the CLI Xcode target as remote SwiftPM
  package references. Justified in Constitution Check + Complexity Tracking; coordinates/Swift-6
  compatibility confirmed at implementation start (research.md D1); in-house fallbacks defined.

**Storage**: Local filesystem, one folder per session (unchanged). **New**: default base output
directory `~/.valistream/sessions/<session-id>/` (platform data dir on non-macOS) when `--output` is
omitted; reports now written **atomically, per refresh cycle** (research.md D5, D6).

**Testing**: Swift Testing. Unit/conformance in the package (`swift test`); integration via the Xcode
`IntegrationTests` scheme / `IntegrationTests.xctestplan` (integration tests only) or
`Valistream` scheme / `Valistream.xctestplan` (full suite) — both with scripted in-process transport
stubs (no server). New unit coverage: alias derivation/stability, output-location resolution +
fail-fast, atomic report writer, unified finalization + partial-report marking, styling gate
(TTY/NO_COLOR/`--no-color`), verbosity gating, progress/activity events. TTY-only paths (prompt,
in-place render) are tested through injected `isTTY`/seams, asserting behavior — not a real terminal.

**Target Platform**: macOS 14+ CLI (unchanged); non-macOS default-path behavior documented (research.md
D5), Linux portability still non-goal.

**Project Type**: Single SwiftPM package (`ValistreamCore` library) + thin CLI tool in an Xcode project,
joined by a workspace (unchanged from feature 001).

**Performance Goals**: displayed activity/progress updates ≥ 1×/second while work is ongoing and the UI
never appears frozen (SC-001, SC-002); graceful-stop shutdown completes ≤ 3 s with in-flight requests
cancelled immediately (SC-003); on-disk reports stale by ≤ one refresh cycle during live monitoring
(SC-006).

**Constraints**: core stays dependency-free; report files contain **no** styling/control bytes; both
reports written atomically (no partial reads); **structured-report schema and exit codes are frozen**
(FR-003, SC-010); English-only; no GUI; segment/bandwidth audit out of scope (deferred).

**Scale/Scope**: unchanged from feature 001 — masters up to ~50 media playlists; live sessions up to
24 h producing many small artifact files; single stream per process.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Spec-First | Approved spec with resolved clarifications before this plan | ✅ spec.md complete; 7 clarifications recorded (2026-06-13); no `NEEDS CLARIFICATION` remain |
| II. Test-First | Plan provides test strategy; tasks generate tests first per story | ✅ unit + scripted-transport integration tests defined per US (Technical Context); tests default-on |
| III. Simplicity | No unjustified projects/abstractions/dependencies | ⚠️ **Two new CLI-target dependencies** (Rainbow, Promptberry). No new projects/layers; core stays pure. Tension recorded in **Complexity Tracking** with in-house fallbacks → accepted |
| IV. Independent Increments | Story slices independently implementable/testable | ✅ US1 (responsive narrated output = MVP) → US2 (graceful stop) → US3 (output dir) → US4 (live/aliased report) → US5 (prompt); each ships independently |
| V. Observability & Versioning | Structured output; semver | ✅ structured report + exit codes **preserved** (FR-003); additive flags only → **MINOR** version bump, no breaking change/migration |

**Initial evaluation**: PASS with one justified deviation (new CLI-target dependencies; see Complexity
Tracking). No `NEEDS CLARIFICATION`.

**Post-design re-evaluation**: PASS — Phase 1 design adds **no** new project or core dependency; the
only dependencies are the two Rainbow/Promptberry CLI-target additions already justified, and they are
isolated, reversible (fallbacks), and never touch the domain core or the report files.

## Project Structure

### Documentation (this feature)

```text
specs/002-performance-ux/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output — decisions D1–D10
├── data-model.md        # Phase 1 output — new presentation/session-control entities
├── quickstart.md        # Phase 1 output — per-US validation scenarios
├── contracts/           # Phase 1 output
│   ├── cli-interface.md       # delta over 001: new flags, startup order, graceful stop, frozen exit codes
│   ├── report-format.md       # human report sections + aliases/legend; JSON schema frozen
│   └── terminal-output.md     # styling gate, progress, spacing, verbosity, prompts
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

Layout is **unchanged** from feature 001 (workspace + package + CLI Xcode project). New/edited files
land in existing modules:

```text
Valistream/
├── Valistream.xcworkspace
├── TestPlans/                                   # ValistreamCore.xctestplan + Valistream.xctestplan + IntegrationTests.xctestplan
├── Valistream/                                  # CLI Xcode project (thin presentation/IO shell)
│   ├── Valistream.xcodeproj                     # set PRODUCT_NAME=valistream (FR-001, D9);
│   │                                            #   add remote packages Rainbow + Promptberry (CLI target)
│   ├── Valistream/                              # CLI sources (FileSystemSynchronized — drop files in)
│   │   ├── ValistreamCommand.swift              # + --verbose/--no-color; mutual-exclusion; output pre-flight
│   │   │                                        #   + 2-stage SIGINT (graceful → force); banner says 'valistream'
│   │   ├── StatusRenderer.swift                 # color (Rainbow) + verbosity + spacing + live progress (TTY/non-TTY)
│   │   ├── TerminalWriter.swift                 # NEW: applies core TerminalOutputMode — plain vs Rainbow, severity palette, blank-line spacing (CLI)
│   │   ├── ProgressView.swift                   # NEW: in-place TTY status line / plain non-TTY lines (CLI)
│   │   ├── PromptberrySelection.swift           # NEW: Promptberry multi-select (replaces/ wraps checklist)
│   │   └── PlaylistChecklist.swift              # retained as fallback (research.md D1/D8)
│   └── ValistreamIntegrationTests/              # + graceful-stop (one-shot+live), non-TTY output, live-report tests
└── ValistreamCore/                              # SwiftPM package — stays dependency-free
    ├── Package.swift                            # unchanged (no new deps)
    ├── Sources/ValistreamCore/
    │   ├── Output/
    │   │   ├── TerminalOutputMode.swift         # NEW: pure styling-gate predicate + Verbosity enum (no Rainbow)
    │   │   └── ProgressFormatter.swift          # NEW: pure activity + counts/percentage formatting
    │   ├── Session/
    │   │   ├── ValidationSession.swift          # unified finish() for completion/stop/limit; cancel-in-flight;
    │   │   │                                    #   one-shot honors stop; per-cycle writeReport; emits activity/progress
    │   │   ├── SessionConfig.swift              # SessionEndReason; (outputDir already present)
    │   │   ├── SessionReportBuilder.swift       # prettified buildMarkdown + alias/legend; buildJSON FROZEN
    │   │   ├── OutputLocation.swift             # NEW: resolve absolute session folder + writability pre-flight
    │   │   ├── PlaylistAlias.swift              # NEW: alias model + AliasRegistry (deterministic, stable, unique)
    │   │   └── …                                # SessionEvent gains an activity/progress case (additive)
    │   └── Archive/
    │       └── SessionArchive.swift             # atomic write helper (temp + replace) for both reports
    └── Tests/ValistreamCoreTests/               # + TerminalOutputMode, ProgressFormatter, PlaylistAlias, OutputLocation, atomic report, finalization, progress-event tests
```

**Structure Decision**: reuse feature 001's structure verbatim. The **domain core remains a pure,
zero-dependency, terminal-free library** (Constitution III): aliases, output-location resolution,
progress events, the pure styling-gate predicate (`TerminalOutputMode`) + `Verbosity`, progress
formatting (`ProgressFormatter`), atomic/live report writing, and unified finalization are all pure
logic added to existing modules (a new `Output/` module plus `Session/`). Every *terminal* concern that
must touch the screen or a library — color *application* (Rainbow), in-place progress *rendering*,
interactive prompts (Promptberry) — lives in the CLI target (`TerminalWriter`, `ProgressView`,
`PromptberrySelection`), which is where the two new dependencies attach — keeping the core reusable
(e.g., by a future GUI) and the new-dependency risk isolated.

## Implementation Guidance

Binding instructions for the implementation phase (`/speckit-tasks` must surface these):

- **Code style**: MUST follow [`styleguide.md`](../../styleguide.md) (repo root).
- **Test development**: MUST follow [`unit-testing.md`](../../unit-testing.md) (repo root).
- **Skills to consult before writing the corresponding code**: `swift-concurrency-pro` (cancellation,
  AsyncStream, unified finalization, render-loop isolation), `swift-testing-pro` (all test code),
  `swift-api-design-guidelines` (new public core API: `PlaylistAlias`, `OutputLocation`),
  `swift-architecture` (core/CLI boundary, dependency isolation), `swift-language` (core idioms).
- **MCP discipline** (CLAUDE.md): use **serena** for code inspection/edit/memory; **xcode-tools** for
  build (`BuildProject`, `XcodeListNavigatorIssues`, `GetBuildLog`) and docs (`DocumentationSearch`).
  **No WebSearch.** Pipe `swift build`/`swift test` through `xcsift`.
- **Dependency verification (binding, do first for US1/US5)**: confirm Rainbow + Promptberry resolve
  under Swift 6 / macOS 14 before importing; if not, use the in-house fallbacks (research.md D1).
- **Frozen contracts**: do not alter the JSON report schema, rule sets/IDs, or exit codes (FR-003).

## Complexity Tracking

> Justifies the one Constitution III deviation: two new CLI-target dependencies.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| New dependency **Rainbow** (color) on CLI target | Delivers the spec's colored-output UX (FR-008/009) without hand-maintaining SGR escape sequences; the feature's explicit goal is a "world-standard CLI" and the user named the library | In-house ANSI helper is feasible (~50 lines) and is kept as the **fallback**; library chosen for ergonomics + user direction. Risk isolated to the non-core CLI target; report files never styled |
| New dependency **Promptberry** (prompts) on CLI target | Delivers the polished multi-select experience headlining US5 (FR-027), beyond the basic termios checklist | Existing termios `PlaylistChecklist` works and is **retained as the fallback**; US5 is P5/optional, so this dependency is reversible and never blocks the feature. Risk isolated to the CLI target |

No new projects, layers, or core dependencies are introduced; the domain core stays pure.

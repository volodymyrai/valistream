# Implementation Plan: Reliable Monitoring and Evidence

**Branch**: `main` (no feature branch — git extension not installed) | **Date**: 2026-06-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-monitoring-evidence/spec.md`

## Summary

Harden the **output and reporting** of the existing HLS validator so the tool reads like a calm
heartbeat monitor and, the instant something is wrong, hands the operator the exact on-disk file(s) to
act on and to escalate. **No validation rule, finding catalog, structured-report schema, or exit code
changes** (FR-001/002, frozen since 001). The work, by priority:

- **US1 — Evidence (P1, MVP):** every ERROR/WARN in terminal and report names the exact archived file
  it was observed in; continuity findings name **both** consecutive snapshots; a missing-body case is
  stated explicitly by ID (never a raw URL). Evidence is recoverable from the frozen structured report
  by joining each finding's `resource` (URL) + `refreshIndex` against the artifact index — **no schema
  change**.
- **US2 — Clutter-free, steady heartbeat (P2):** a start-of-session roster (ID → URL + role), then
  ID-only body output (zero raw URLs anywhere but roster/legend), descriptive wording, a **monotonic**
  in-place heartbeat resilient to stray keystrokes, and a genuinely richer `--verbose` trace tier.
- **US3 — Meaningful IDs (P3):** rework feature 002's alias scheme into `master` / `<height>p_<codecs>`
  (e.g. `1080p_avc1`) / role-based audio/subtitle/I-frame IDs, deterministic + stable + unique; a
  specific refresh is the indexed form `<id>_<n>` that also names its archived snapshot file.
- **US4 — Process-all-by-default (P4):** all renditions process with no prompt by default (even on a
  TTY); remove `--all`; add `--preselect <pattern>` (former `--select` behavior); repurpose `--select`
  to raise the interactive checklist.
- **US5 — Pretty JSON files (P5):** pretty-print every JSON file written to disk (report + metadata
  sidecars); the line-delimited `--json` status stream stays one compact object per line.

**Technical approach:** keep `ValistreamCore` a **pure, zero-external-dependency** library — all new
logic is pure and additive: the reworked ID scheme (`PlaylistAlias`/`AliasRegistry`), a pure
**evidence resolver**, a session-wide **monotonic refresh counter** carried on the existing activity
event, a snapshot-labelled **archive naming** change, additive **trace events** for the verbose tier,
and a **separate pretty JSON encoder** for files. The *presentation* deltas (ID-based finding lines
with evidence, roster print, per-refresh status line, verbose-tier gating, terminal echo suppression
for the heartbeat) live in the thin CLI target, which keeps its 002 dependencies (Rainbow, Promptberry)
and adds **none**. Decisions in [research.md](research.md); entities in [data-model.md](data-model.md);
behavior deltas in [contracts/](contracts/).

## Technical Context

**Language/Version**: Swift 6.x (strict concurrency), SwiftPM + Xcode workspace
(`Valistream.xcworkspace`) — unchanged from 001/002. (`swift-tools-version: 6.3`; CLI target
`SWIFT_VERSION = 6.0`.)

**Primary Dependencies**:
- *Core* (`ValistreamCore`): Foundation only — **zero external dependencies** (unchanged). Terminal
  echo suppression uses POSIX `termios` (already used by the CLI's `PlaylistChecklist`), not a new dep.
- *CLI target* (`Valistream`): `swift-argument-parser` + **Rainbow** + **Promptberry** — exactly the
  002 set. **No new dependency is added by this feature** (Constitution III: PASS).

**Storage**: Local filesystem, one folder per session (unchanged). **Change (FR-029):** archived
snapshots are renamed from `playlists/<id>/NNNNNN.m3u8` to **`playlists/<id>/<id>_<n>.m3u8`** with a
matching `<id>_<n>.meta.json` sidecar, where `<id>` is the playlist's presentation ID and `<n>` its
0-based per-playlist refresh index — so every evidence file is self-identifying. Reports and sidecars
are now **pretty-printed** (FR-026); writes stay atomic (002).

**Testing**: Swift Testing. Unit/conformance in the package (`swift test`); integration via the Xcode
`Valistream` scheme / `Valistream.xctestplan` with scripted in-process transport stubs (no server).
New unit coverage: ID-scheme derivation (`1080p_avc1`, `audio_en`, dedup, fallback, codec trimming,
slugging), evidence resolution (single / continuity-pair / unavailable), monotonic refresh counter,
archive snapshot naming, pretty vs compact JSON encoders, verbose trace formatting, selection-policy
(`--preselect`/`--select`/default). Integration: evidence-in-output end-to-end, roster + zero-URL body,
heartbeat monotonicity under stray input (seam-injected), verbose-vs-normal distinctness, selection
matrix. TTY-only paths (in-place render, echo suppression) are tested through injected seams, asserting
behavior — not a real terminal.

**Target Platform**: macOS 14+ CLI (unchanged); non-macOS default-path behavior inherited from 002;
Linux portability still a non-goal.

**Project Type**: Single SwiftPM package (`ValistreamCore` library) + thin CLI tool in an Xcode
project, joined by a workspace (unchanged from 001/002).

**Performance Goals**: inherited from 002 (activity/progress ≥ 1×/s, never-frozen UI, graceful stop
≤ 3 s, on-disk report stale by ≤ one refresh cycle). **New (SC-004):** across a 30-minute live session
with ≥ 20 stray Enter presses, the displayed refresh count is monotonic non-decreasing and equals the
actual number of refreshes (zero backward jumps, zero miscounts).

**Constraints**: core stays dependency-free; report files contain **no** styling/control bytes;
**structured-report schema, validation rules, and exit codes are FROZEN** (FR-001/002); **zero raw
playlist URLs** outside the roster and report legend at *every* verbosity tier including `--verbose`
(SC-003); evidence is **whole-file only** (no in-file line/segment locus); English-only; no GUI;
segment/bandwidth audit still out of scope.

**Scale/Scope**: unchanged from 001/002 — masters up to ~50 media playlists; live sessions up to 24 h
producing many small artifact files; single stream per process.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Spec-First | Approved spec with resolved clarifications before this plan | ✅ spec.md complete; **12 clarifications** recorded (2026-06-14); no `NEEDS CLARIFICATION` remain |
| II. Test-First | Plan provides test strategy; tasks generate tests first per story | ✅ unit + scripted-transport integration tests defined per US (Technical Context); tests default-on |
| III. Simplicity | No unjustified projects/abstractions/dependencies | ✅ **No new dependency, project, or layer.** All new logic is pure + additive in existing core modules; presentation deltas in the existing CLI target. Reuses 002's Rainbow/Promptberry and the existing `termios` seam |
| IV. Independent Increments | Story slices independently implementable/testable | ✅ US1 (evidence = MVP) → US2 (heartbeat) → US3 (IDs) → US4 (selection) → US5 (pretty JSON); each ships independently. Cross-cutting ID work that US1's archive naming needs is isolated in the Foundational phase |
| V. Observability & Versioning | Structured output; semver + migration on breaking change | ✅ **Breaking CLI change** (`--all` removed; `--select` repurposed; `--select <pattern>` → `--preselect`) ships **0.3.0** (minor) with migration notes (FR-003). **Compliant with Constitution V (v1.1.0)**: the `0.y.z` carve-out requires a pre-1.0 breaking change to bump at least MINOR and provide a migration path — both satisfied. No deviation |

**Initial evaluation**: PASS — no deviations. The pre-1.0 breaking-change versioning is explicitly
permitted by Constitution V's `0.y.z` carve-out (v1.1.0, 2026-06-14). No new dependencies. No
`NEEDS CLARIFICATION`.

**Post-design re-evaluation**: PASS — Phase 1 design introduces **no** new project, dependency, or core
abstraction beyond pure additive types (`EvidenceReference`/resolver, trace events, a second JSON
encoder constant, a monotonic counter field). The frozen JSON schema, rule set, and exit codes are
untouched; the only structured-report change is whitespace (pretty-print) and artifact-index path
*values* (FR-029) — both explicitly permitted. **No Constitution deviations remain**: the earlier pre-1.0
versioning concern is resolved by Constitution V's `0.y.z` carve-out (v1.1.0).

## Project Structure

### Documentation (this feature)

```text
specs/003-monitoring-evidence/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output — decisions D1–D12
├── data-model.md        # Phase 1 output — ID/evidence/heartbeat/trace entities (presentation-layer)
├── quickstart.md        # Phase 1 output — per-US validation scenarios
├── contracts/           # Phase 1 output (deltas over 001/002 — nothing frozen is restated as new)
│   ├── cli-interface.md       # selection-flag rework, version/migration, frozen exit codes
│   ├── terminal-output.md     # verbosity catalog, roster, per-refresh line, monotonic+input-resilient heartbeat
│   ├── evidence-and-ids.md    # ID grammar, snapshot index, archive naming, evidence resolution + unavailable rule
│   └── report-format.md       # markdown evidence spans + legend; JSON schema FROZEN; pretty-print files only
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

Layout is **unchanged** from 001/002 (workspace + package + CLI Xcode project). All edits land in
existing files; new files are pure core types. No directory is added.

```text
Valistream/
├── Valistream.xcworkspace
├── TestPlans/                                    # ValistreamCore.xctestplan + Valistream.xctestplan
├── Valistream/                                   # CLI Xcode project (thin presentation/IO shell)
│   ├── Valistream.xcodeproj                      # bump MARKETING_VERSION 0.2.0 → 0.3.0 (FR-003)
│   ├── Valistream/                               # CLI sources (FileSystemSynchronized — drop files in)
│   │   ├── ValistreamCommand.swift               # FR-021–025: remove --all; add --preselect; --select=flag;
│   │   │                                         #   mutual-exclusion (exit 2); non-TTY --select → all + notice
│   │   ├── StatusRenderer.swift                  # renderFinding: ID + evidence, NO raw URL (US1/US2/US3);
│   │   │                                         #   roster + per-refresh status line + verbose trace gating;
│   │   │                                         #   --json stays COMPACT (FR-028)
│   │   ├── ProgressView.swift                    # heartbeat: show monotonic total + current ID (FR-013)
│   │   ├── TerminalWriter.swift                  # (reused; severity palette, spacing)
│   │   ├── LiveInputGuard.swift                  # NEW (CLI): termios echo/canon suppression during live TTY
│   │   │                                         #   monitoring + restore on exit (FR-014). Wraps existing seam
│   │   ├── PromptberrySelection.swift            # (reused for --select checklist)
│   │   └── PlaylistChecklist.swift               # retained fallback
│   └── ValistreamIntegrationTests/               # + evidence-in-output, roster/zero-URL, heartbeat-monotonic,
│                                                 #   verbose-vs-normal, selection-matrix, pretty-JSON tests
└── ValistreamCore/                               # SwiftPM package — stays dependency-free
    ├── Sources/ValistreamCore/
    │   ├── Session/
    │   │   ├── PlaylistAlias.swift               # REWORK AliasRegistry → ID scheme: master / <height>p_<codecs>
    │   │   │                                     #   / audio_<lang>/subs_<lang>/iframe_<height>p; codec fourCC
    │   │   │                                     #   trim+join("-"); slug; dedup; role+ordinal fallback (FR-016–020)
    │   │   ├── SnapshotID.swift                  # NEW: pure <id>_<n> formatting/parsing (FR-018a)
    │   │   ├── EvidenceResolver.swift            # NEW: pure Finding → EvidenceReference (single / pair /
    │   │   │                                     #   unavailable-by-ID) over registry + archive index (FR-004–009)
    │   │   ├── SessionConfig.swift               # SessionEvent: additive .rosterReady / .refreshCompleted /
    │   │   │                                     #   .trace cases; ActivityProgress: monotonic session total field
    │   │   ├── SessionReportBuilder.swift        # markdown: evidence code-spans + ID legend (FR-005);
    │   │   │                                     #   buildJSON: use prettyJSONEncoder; report VALUES frozen (FR-002)
    │   │   ├── ValidationSession.swift           # own the single AliasRegistry; assign IDs at discovery;
    │   │   ├── ValidationSession+Reporting.swift # pass real <id> to archive.store; emit trace/refresh events
    │   │   └── ValidationSession+Monitoring.swift# bump session-wide monotonic refresh counter per refresh
    │   ├── Archive/
    │   │   └── SessionArchive.swift              # store(): filename <id>_<n>.m3u8 / .meta.json (FR-029);
    │   │                                         #   meta sidecar via prettyJSONEncoder (FR-026)
    │   ├── Output/
    │   │   ├── ProgressFormatter.swift           # heartbeat wording: "<id> · refresh <total> · <elapsed>"
    │   │   └── TraceFormatter.swift              # NEW: pure category-prefixed ID-based verbose lines (FR-015b)
    │   └── Validation/
    │       └── Finding.swift                     # add `prettyJSONEncoder` constant; compact `jsonEncoder` KEPT
    │                                             #   for --json NDJSON (FR-028). Struct fields UNCHANGED (FR-002)
    └── Tests/ValistreamCoreTests/                # + ID-scheme, SnapshotID, EvidenceResolver, monotonic-counter,
                                                  #   archive-naming, pretty/compact-encoder, TraceFormatter tests
```

**Structure Decision**: reuse 001/002's structure verbatim; add **no** directory and **no** dependency.
The domain core stays a **pure, zero-dependency, terminal-free** library (Constitution III): the ID
scheme, snapshot labels, evidence resolution, monotonic counting, archive naming, trace formatting, and
the pretty encoder are all pure logic added to existing modules (plus three small new pure files:
`SnapshotID`, `EvidenceResolver`, `TraceFormatter`). Every concern that must touch the screen — ID/
evidence finding lines, roster printing, per-refresh status, verbose gating, and **terminal echo
suppression** for the heartbeat — lives in the CLI target (`StatusRenderer`, `ProgressView`, the new
`LiveInputGuard`), keeping the core reusable and the TTY/termios risk isolated.

## Implementation Guidance

Binding instructions for the implementation phase (`/speckit-tasks` must surface these):

- **Code style**: MUST follow [`styleguide.md`](../../styleguide.md) (repo root).
- **Test development**: MUST follow [`unit-testing.md`](../../unit-testing.md) (repo root).
- **Skills to consult before writing the corresponding code**: `swift-api-design-guidelines` (new
  public core API: `EvidenceReference`/resolver, `SnapshotID`, reworked `AliasRegistry`, trace types),
  `swift-concurrency-pro` (monotonic counter under the session actor; render-loop / event-stream
  isolation; termios restore on cancellation), `swift-testing-pro` (all test code), `swift-language`
  (ID grammar building, slugging, codec trimming with modern collection/string APIs),
  `swift-architecture` (core/CLI boundary; keep termios + color in CLI).
- **MCP discipline** (CLAUDE.md): use **serena** for code inspection/edit/memory; **xcode-tools** for
  build (`BuildProject`, `XcodeListNavigatorIssues`, `GetBuildLog`, `XcodeRefreshCodeIssuesInFile`) and
  docs (`DocumentationSearch`). **No WebSearch.** Pipe `swift build`/`swift test` through `xcsift`.
  Bash code inspection requires explicit permission.
- **Frozen contracts (do NOT touch)**: the JSON report **schema, field names, types, and values**
  (incl. `playlists[].id`); the rule set / rule IDs / finding catalog; exit codes (0/1/2/3, 130). The
  only permitted structured-report changes are pretty-print whitespace (FR-026) and artifact-index path
  *values* (FR-029). Evidence recovery joins on a finding's **`resource` URL + `refreshIndex`**, never
  on `playlists[].id` — keep these two identifiers distinct.
- **Encoder discipline**: the `--json` NDJSON stream MUST keep the **compact** `Finding.jsonEncoder`
  (one object per line, FR-028); only files (report + `*.meta.json`) use the new `prettyJSONEncoder`.
- **Version**: set `MARKETING_VERSION = 0.3.0`; `--version`/help document every option and call the
  selection changes out as breaking with migration guidance (FR-003).

## Complexity Tracking

> No Constitution deviations remain; none require justification.

**None.** A prior concern — versioning the breaking CLI change (`--all` removed, `--select` repurposed)
as a MINOR `0.3.0` bump rather than `1.0.0` — was recorded here as a deviation under Constitution
v1.0.0's literal "breaking → MAJOR" rule. Constitution **v1.1.0** (2026-06-14) added an explicit `0.y.z`
carve-out to Principle V: a pre-1.0 breaking change MUST bump at least MINOR and ship a documented
migration path (FR-003) — which this feature does. The versioning is therefore **compliant, not a
deviation**, so no Complexity Tracking entry is needed.

No new projects, layers, dependencies, or core abstractions beyond pure additive types; the domain core
stays pure and dependency-free.

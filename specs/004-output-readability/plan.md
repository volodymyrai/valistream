# Implementation Plan: Readable Output and Onboarding (004)

**Branch**: `main` (no feature branch — work proceeds on `main`) | **Date**: 2026-06-15 |
**Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/004-output-readability/spec.md`

**Design artifacts**: [research.md](./research.md) · [data-model.md](./data-model.md) ·
[contracts/](./contracts/) · [quickstart.md](./quickstart.md)

## Summary

Feature 004 raises stdout and Markdown-report readability across quiet/normal/verbose modes and rewrites
`README.md` as a complete GitHub onboarding guide, shipping `0.4.0`. It is **presentation-only**: the
validation engine, finding/playlist/snapshot identifiers, evidence resolution, selection behavior, the
structured JSON report (schema v1), JSON Lines, the `--json` stream, and exit codes 0/1/2/3/130 are
**frozen** (FR-002/FR-028).

The codebase already ships a color/verbosity output layer (features 002/003): `TerminalOutputMode`
(color gating), `TerminalWriter` (Rainbow styling), `ProgressFormatter`/`TraceFormatter`, `ProgressView`
heartbeat, `--no-color`/`NO_COLOR`/`TERM=dumb` handling, and `Finding.observedAt`. The plan therefore
**refines and extends** that layer rather than building it new. Technical approach (see research D1–D15):

1. **Occurrence timestamps** on every human-readable message via a `TimestampedEvent` envelope + two pure
   formatters (terminal `[HH:mm:ss.SSS]` local; report ISO-8601 local with offset).
2. **Blank-line grammar** — a block-emitting writer that puts exactly one blank line between logical groups
   and none within them, disabled for the `--json` machine stream (**user directive**).
3. **Whole-line severity tint + presentation roles + Unicode/ASCII status markers**.
4. **One persistent result per refresh** (collapse duplicate stage messages; detail moves to verbose).
5. **Playlist information block** — a one-time, first-load engineering summary (master/media field sets,
   protection classification) shown in normal/verbose terminal and the report, omitted in quiet. Needs one
   minimal **additive** metadata surface on the playlist model (declared `EXT-X-KEY`/`EXT-X-SESSION-KEY`
   method+keyformat) — no validation change.
6. **Incident timeline** in the Markdown report (timestamped, links to severity-grouped findings, no
   duplication) + **playlist lifecycle events**.
7. **README rewrite** with verifiable badges incl. **code coverage** (from the now-enabled
   `Valistream.xctestplan`), `valistream-cli.zip` primary install, verified quick-start stream.
8. **Version 0.4.0** + **compatibility guard tests** proving the frozen surfaces are unchanged.

## Technical Context

**Language/Version**: Swift 6 — `ValistreamCore` package `swift-tools-version 6.3`, `swiftLanguageModes
[.v6]` (strict concurrency); CLI Xcode target `SWIFT_VERSION 6.0`. Platforms: macOS 14+.

**Primary Dependencies**: `ValistreamCore` = **Foundation-only, no external dependency**. CLI target:
`swift-argument-parser` (1.8.x), **Rainbow** (terminal color — already adopted), **Promptberry** (prompts).
**No new dependency is introduced** (Rainbow is reused; FR-009a/Assumption satisfied).

**Storage**: filesystem session folder via the existing `SessionArchive` (`<outputDir>/<sessionID>/…`).
No database.

**Testing**: Swift Testing (`unit-testing.md` rules). Unit/conformance → `swift test` in
`Valistream/ValistreamCore/` (`ValistreamCoreTests`). Integration → `Valistream` scheme /
`Valistream/TestPlans/Valistream.xctestplan` (`ValistreamCoreTests` + `ValistreamIntegrationTests`).
**Coverage** is enabled in `Valistream.xctestplan` (`codeCoverage` for `Valistream` + `ValistreamCore`),
read via `xcrun xccov` (research D15) for the README badge (FR-029a, SC-010).

**Target Platform**: macOS 14+ command-line tool (`valistream`).

**Project Type**: single project — a Swift library + CLI in one Xcode workspace.

**Performance Goals**: output/formatting is O(1) per message; no regression to monitoring cadence
(RFC 8216 §6.3.4 refresh timing) or to validation throughput. The blank-line grammar and timestamping add
negligible overhead.

**Constraints**:
- `ValistreamCore` stays Foundation-only and dependency-free.
- Frozen machine surfaces (FR-002/FR-028): validation results, IDs, evidence, JSON schema v1, `.meta.json`,
  `FindingsLog` JSONL, `--json` stream, selection, exit codes.
- Plain-text baseline: zero styling/cursor-control bytes when non-interactive / `NO_COLOR` / `--no-color` /
  `TERM=dumb` (FR-012, SC-005).
- Terminal palette: restrained 8/16 ANSI only; legible at 80/120 columns (FR-009a, FR-014, SC-006).
- README examples are plain-text only; no committed credentials/expiring URLs (FR-033/034).

**Scale/Scope**: ~7 CLI source files, 3 Core `Output/` formatters, the report builder, the playlist model
(additive), plus new info/timeline/lifecycle models and the README. 38 functional requirements, 5
prioritized user stories, 13 measurable success criteria.

## Constitution Check

*Constitution v1.1.0. GATE: must pass before Phase 0 and be re-checked after Phase 1.*

| Principle | Assessment | Verdict |
|---|---|---|
| **I. Spec-First** | Approved spec exists with 19 clarifications resolved (Session 2026-06-15); this plan + artifacts complete the gate; zero `NEEDS CLARIFICATION` remain. | ✅ Pass |
| **II. Test-First (NON-NEGOTIABLE)** | Every behavior change ships tests first (Red-Green-Refactor): timestamp formatters, blank-line grammar, tint/markers, info block, protection classifier, incident timeline, lifecycle, compatibility guards, README verification. No test waiver requested. | ✅ Pass |
| **III. Simplicity / YAGNI** | Reuses the existing output layer and Rainbow; adds only models the spec mandates. The single non-presentation change — additive `EXT-X-KEY`/`EXT-X-SESSION-KEY` metadata on the playlist model — is required by FR-017b/e/f and is read-only (no rule/layer added). | ✅ Pass |
| **IV. Independent, testable increments** | User stories are pre-prioritized P1–P4 and independently testable (quickstart maps each). P1 (live-session readability) is a viable MVP on its own. | ✅ Pass |
| **V. Observability & Versioning** | Structured/greppable output preserved (machine streams frozen). `0.3.0 → 0.4.0` MINOR bump for a pre-1.0 series; human-readable output reshaping is documented as a migration note (README/help). No machine-contract break. | ✅ Pass |

**Result**: PASS, no violations → Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/004-output-readability/
├── plan.md              # This file (/speckit-plan)
├── research.md          # Phase 0 — decisions D1–D15
├── data-model.md        # Phase 1 — entities
├── quickstart.md        # Phase 1 — validation guide
├── contracts/           # Phase 1 — terminal-output.md, report-format.md, readme.md, compatibility.md
└── tasks.md             # Phase 2 (/speckit-tasks — NOT created here)
```

### Target → source-folder paths (READ THIS BEFORE CREATING FILES)

Use the **filesystem path from repo root** for Serena, shell, git, and file creation. The integration test
target and the CLI tool target both live under the **doubled** `Valistream/Valistream/...` workspace folder.
The Xcode **navigator** shows shorter paths — never create files at the navigator path.

| Target / area | Filesystem path from repo root (USE THIS) | Xcode navigator path |
|---|---|---|
| Workspace | `Valistream/Valistream.xcworkspace/` | workspace root |
| `ValistreamCore` package root | `Valistream/ValistreamCore/` | `ValistreamCore/` |
| `ValistreamCore` production sources | `Valistream/ValistreamCore/Sources/ValistreamCore/` | `ValistreamCore/Sources/ValistreamCore/` |
| `ValistreamCoreTests` (unit/conformance) | `Valistream/ValistreamCore/Tests/ValistreamCoreTests/` | `ValistreamCore/Tests/ValistreamCoreTests/` |
| `Valistream` CLI tool sources | `Valistream/Valistream/Valistream/` | `Valistream/Valistream/` |
| `ValistreamIntegrationTests` | `Valistream/Valistream/ValistreamIntegrationTests/` | `Valistream/ValistreamIntegrationTests/` |
| Xcode project | `Valistream/Valistream/Valistream.xcodeproj/` | project `Valistream` |
| Test plans | `Valistream/TestPlans/` | `TestPlans/` |

> ⚠️ The CLI tool sources are at `Valistream/Valistream/Valistream/` (triple `Valistream`) and the
> integration tests at `Valistream/Valistream/ValistreamIntegrationTests/`. Specs that write
> `IntegrationTests` or `ValistreamCore/...` mean these full workspace paths — e.g.
> `IntegrationTests` → `Valistream/Valistream/ValistreamIntegrationTests`. Verify with `XcodeGlob`/Serena
> before adding a file.

### Source code (repository root) — touched & new files

```text
# ── ValistreamCore (Foundation-only library) ──────────────────────────────────────────
Valistream/ValistreamCore/Sources/ValistreamCore/
├── Output/
│   ├── TerminalOutputMode.swift        # EXTEND: add GlyphStyle (unicode/ascii) + UTF-8 detection
│   ├── ProgressFormatter.swift         # reuse (heartbeat text; no ANSI)
│   ├── TraceFormatter.swift            # reuse (verbose category lines)
│   ├── TimestampFormatter.swift        # NEW: terminal [HH:mm:ss.SSS] + report ISO-8601 (+offset)
│   ├── PresentationRole.swift          # NEW: role enum (heading/identifier/success/.../summary)
│   └── PlaylistInfoFormatter.swift     # NEW: render PlaylistInformation (terminal + markdown text)
├── Playlist/
│   ├── PlaylistModel.swift             # EXTEND (additive, read-only): EXT-X-KEY/EXT-X-SESSION-KEY method+keyformat
│   ├── PlaylistBuilder.swift           # EXTEND: populate the additive key metadata it already tokenizes
│   ├── PlaylistInformation.swift       # NEW: MasterInfo/MediaInfo value + pure builder from PlaylistModel
│   └── PlaylistProtection.swift        # NEW: classify → None / Encrypted (AES-128) / DRM(<keyformat>)
├── Session/
│   ├── SessionConfig.swift             # EXTEND: SessionEvent + .playlistInformation/.playlistLifecycle; TimestampedEvent envelope
│   ├── PlaylistLifecycleEvent.swift    # NEW: unavailable/recovered/added/removed/identityChanged
│   ├── IncidentTimeline.swift          # NEW: TimelineEntry/TimelineKind, ordered (at, sequence)
│   ├── SessionReportBuilder.swift      # EXTEND: timeline + info-block sections + timestamps + callouts (markdown only)
│   ├── ValidationSession.swift         # EXTEND: stamp events at occurrence; timelineSequence; loaded-info set
│   ├── ValidationSession+Monitoring.swift # EXTEND: emit lifecycle events from monitor/staleness/roster-diff
│   └── ValidationSession+Reporting.swift  # EXTEND: record timeline entries; emit playlistInformation once
└── (Validation/Finding.swift           # reuse: observedAt, jsonEncoder, prettyJSONEncoder — UNCHANGED)

# ── Valistream CLI tool (Xcode target) ────────────────────────────────────────────────
Valistream/Valistream/Valistream/
├── ValistreamCommand.swift             # EXTEND: version 0.3.0→0.4.0; pass GlyphStyle; --help/version copy
├── StatusRenderer.swift                # EXTEND: timestamps, block grouping, persistent result, info block, lifecycle
├── TerminalWriter.swift                # EXTEND: whole-line severity tint, role styling, markers, block writer
├── ProgressView.swift                  # reuse: keep heartbeat transient & non-competing (FR-024)
├── LiveInputGuard.swift                # reuse
├── PlaylistChecklist.swift             # reuse
└── PromptberrySelection.swift          # reuse

# ── Tests ─────────────────────────────────────────────────────────────────────────────
Valistream/ValistreamCore/Tests/ValistreamCoreTests/
├── Output/ TimestampFormatterTests, PresentationRoleTests, PlaylistInfoFormatterTests, (TerminalOutputMode glyph) 
├── Playlist/ PlaylistInformationTests, PlaylistProtectionTests
└── Session/ IncidentTimelineTests, PlaylistLifecycleEventTests, SessionReport(timeline/info)Tests
Valistream/Valistream/ValistreamIntegrationTests/
├── BlankLineGroupingTests        # NEW: one blank line between groups, none within (user directive)
├── TimestampedOutputTests        # NEW: every human line timestamped; machine stream not
├── PlaylistInfoBlockTests        # NEW: once-per-playlist, quiet omits, normal/verbose/report parity
├── IncidentTimelineReportTests   # NEW: ordering, links, no duplication
├── VerbosityEquivalenceTests     # NEW: findings/evidence/report/exit identical across tiers
└── CompatibilityFreezeTests      # NEW: --json/JSONL/schema/exit unchanged (+ reuse 003 guards)

# ── Repo root / project config ────────────────────────────────────────────────────────
README.md                                          # REWRITE (FR-029–037) with badges incl. coverage
Valistream/Valistream/Valistream.xcodeproj/project.pbxproj   # MARKETING_VERSION 0.3.0→0.4.0 (all configs)
Valistream/TestPlans/Valistream.xctestplan         # coverage already enabled (source for badge)
```

**Structure Decision**: Single-project layout is unchanged. New Core types are pure values in
`ValistreamCore` `Output/`, `Playlist/`, and `Session/`; presentation wiring stays in the CLI target. This
keeps `ValistreamCore` Foundation-only and dependency-free, and confines Rainbow/terminal concerns to the
CLI, consistent with features 001–003.

## Complexity Tracking

No constitution violations — table intentionally empty. The one non-presentation change (additive,
read-only playlist key metadata for protection classification) is required directly by FR-017b/e/f, adds no
new rule/layer/dependency, and is therefore not a tracked complexity.

## Phase 0 — Outline & Research

Complete. All unknowns resolved in [research.md](./research.md) (decisions D1–D15). No `NEEDS CLARIFICATION`
remains in Technical Context.

## Phase 1 — Design & Contracts

Complete. Generated [data-model.md](./data-model.md), [contracts/](./contracts/)
(terminal-output, report-format, readme, compatibility), and [quickstart.md](./quickstart.md). Agent context
updated (see below).

### Post-Design Constitution Re-Check

Re-evaluated after design: still **PASS**. The design adds no new dependency or layer; the additive playlist
metadata remains the only non-presentation touch and is spec-mandated; all frozen surfaces are protected by
explicit compatibility contracts and guard tests (Principles II, III, V upheld). Complexity Tracking remains
empty.

## Phase 2 — Next

`/speckit-tasks` to generate the dependency-ordered `tasks.md` (grouped by user story, test-first), then
`/speckit-analyze` for cross-artifact consistency before `/speckit-implement`.

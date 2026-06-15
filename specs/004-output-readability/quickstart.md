# Quickstart & Validation: Readable Output and Onboarding (004)

**Feature**: 004-output-readability | **Date**: 2026-06-15

This is a run/validation guide proving feature 004 end-to-end. It references
[contracts/](./contracts/) and [data-model.md](./data-model.md) instead of duplicating detail.
Implementation steps belong in `tasks.md`.

## Prerequisites

- macOS 14+, Xcode with the Swift 6 toolchain.
- Workspace: `Valistream/Valistream.xcworkspace` (xcode-tools tab `windowtab1`).
- Build / test commands (binding):
  - Build: xcode-tools `BuildProject` (workspace) — resolves packages, compiles `ValistreamCore` + CLI.
  - Unit/conformance: `swift test` inside `Valistream/ValistreamCore/` (`ValistreamCoreTests`).
  - Integration + coverage: `Valistream` scheme / `Valistream/TestPlans/Valistream.xctestplan`
    (xcode-tools `RunAllTests` / `RunSomeTests`). `codeCoverage` is enabled for `Valistream` +
    `ValistreamCore`.
- Pipe `xcodebuild`/`swift test` output through `xcsift` for structured logs.

## Build & test gate

1. `BuildProject` → green, **0 navigator warnings** (`XcodeListNavigatorIssues`).
2. `swift test` (package) → all unit/conformance green.
3. `RunAllTests` (Valistream scheme) → all unit + integration green, including the 003 frozen-surface guards
   (no regression).

## Coverage (user-enabled source, research D15)

1. Run the `Valistream` scheme tests with a result bundle (coverage enabled by the xctestplan).
2. Extract line coverage: `xcrun xccov view --report --json <Result.xcresult>`.
3. Use the measured percentage for the README coverage badge (contracts/readme B3). The badge MUST reflect
   this current value (FR-029a, SC-010); omit it if it cannot be verified.

## Scenario validation (maps to user stories)

Run with scripted in-process transports (integration test harness) for determinism; use real streams for
manual acceptance (below).

### US1 — Follow a live session at a glance (P1) — terminal-output T5–T13, T25, T30, SC-001/002/012
- Run a normal session with several playlists, successful refreshes, and one warning.
- **Expect**: named groups separated by **exactly one blank line** (T9–T13, **user directive**); **one**
  persistent timestamped result per successful refresh (T25, SC-002); a warning's summary+findings+evidence
  in one contiguous block (T11); one playlist information block per playlist at first load (T30, SC-012); a
  prominent final summary with outcome, counts, elapsed time, report path (T36).

### US2 — Find actionable problems immediately (P2) — terminal-output T22–T24; report R1–R12, SC-004/008
- Run a multi-severity stream; capture quiet stdout and open the Markdown report.
- **Expect (quiet)**: all warnings/errors/notices/summary, zero routine success/diagnostic lines (SC-004);
  findings grouped by playlist/snapshot with evidence attached (T24).
- **Expect (report)**: outcome-first summary; one incident timeline (errors/warnings/failures/lifecycle,
  no routine refreshes) ordered by time then sequence; each finding timeline entry links to one complete
  severity-grouped finding with no duplication (R8–R12, SC-008a/b/c).

### US3 — Diagnose deeply without losing context (P3) — terminal-output T27–T29; compatibility V3, SC-007/011
- Compare normal vs verbose captures of the same scripted session.
- **Expect**: verbose nests every diagnostic category under playlist/snapshot context, subordinate to
  results/findings (T27/T28); findings, evidence, reports, structured output, and exit status are identical
  across tiers (T29, V3, SC-011).

### US4 — Start from the README (P4) — contracts/readme, SC-009/010
- Follow only `README.md` to determine platform support, install via a documented path, run a first
  validation, and locate the report/evidence.
- **Expect**: full GitHub structure; verifiable badges incl. coverage; primary `valistream-cli.zip` install;
  copy-paste quick start against a verified public stream; plain-text examples for every output mode; zero
  doc-vs-binary differences (SC-010).

## Compatibility validation (FR-002/028, SC-011) — compatibility.md
- `--json` stream for a scripted session: no timestamps, no blank-line grammar, no ANSI; structurally
  identical to pre-004 (V2).
- 003 guards (`ReportJSONSchemaTests`, RuleEngine/conformance, exit codes) green (V1).

## Styling-disabled validation (FR-012, SC-005/006)
- Redirect stdout to a file and run with `NO_COLOR=1`, `--no-color`, and `TERM=dumb`.
- **Expect**: zero styling/cursor-control bytes; ASCII markers `[OK]/[WARN]/[ERR]` when Unicode is
  unavailable; at 80- and 120-col widths nothing essential is silently truncated (T17–T21).

## Manual acceptance (FR-038, real streams — conversation-only)
- Use the user-supplied **live "TV Nord"** and **VOD "NRK news"** URLs (retrieved from the conversation,
  never committed) to validate live roster/heartbeat/Ctrl-C, the playlist information block (incl.
  protection classification on protected vs unprotected renditions), timestamps, and report readability.
- Any committed example MUST use sanitized URLs and output (FR-034).

## Done when
- All scenarios pass; build green with 0 warnings; coverage measured and badge verified; README verified
  against the `0.4.0` binary; frozen surfaces unchanged.

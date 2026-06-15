# Bug Fix: Staleness Evidence Uses the Correct Baseline

- **Slug**: refresh-interval-stale-warning
- **Fixed**: 2026-06-15
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

Kept the intentional half-target retry cadence and changed staleness evidence to reference the last
playlist body that changed plus the refresh that confirmed the stale threshold. Pairwise continuity
findings still use consecutive previous/current snapshots.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Valistream/ValistreamCore/Sources/ValistreamCore/Session/EvidenceResolver.swift` | modified | Accepts an optional baseline refresh index while preserving consecutive-pair defaults. |
| `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift` | modified | Passes finding-specific evidence baseline metadata without changing `Finding` or JSON schemas. |
| `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift` | modified | Tracks the last changed refresh index and uses it for staleness findings. |
| `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Reporting.swift` | modified | Reuses evidence captured when findings were emitted during Markdown report regeneration. |
| `Valistream/ValistreamCore/Sources/ValistreamCore/Session/SessionReportBuilder.swift` | modified | Supports per-finding evidence overrides while retaining resolver fallback behavior. |
| `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/EvidenceResolverTests.swift` | added test | Pins `_82`/`_84` baseline and threshold-confirming resolution. |
| `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/ReportMarkdownTests.swift` | added test | Pins Markdown rendering to `_82`/`_84` and excludes `_83`. |
| `Valistream/Valistream/ValistreamIntegrationTests/LiveFaultScenarioTests.swift` | updated test | Verifies emitted and reported warning evidence use initial/confirming snapshots. |
| `specs/003-monitoring-evidence/contracts/evidence-and-ids.md` | modified | Defines staleness as a two-reference baseline/current pair. |

## Tests Added or Updated

- `EvidenceResolverTests/stalenessResolvesBaselineAndConfirmingSnapshot()` - proves an intermediate
  unchanged retry is not selected as the baseline.
- `ReportMarkdownTests/stalenessReportPreservesBaselineAndConfirmingEvidence()` - proves report
  regeneration preserves the emitted staleness pair.
- `LiveFaultScenarioTests/stallingPlaylistWarnsThenErrors()` - proves live warning evidence and the
  generated Markdown report both use `_0`/`_2`, not `_1`/`_2`.

## Local Verification

- Commands run: Xcode `ExecuteSnippet` - resolved `video_1_82.m3u8` and `video_1_84.m3u8`.
- Commands run: Xcode `RunSomeTests` - 3 targeted tests passed.
- Commands run: `swift test 2>&1 | xcsift -f toon` from `Valistream/ValistreamCore` - 263 tests passed.
- Commands run: Xcode `BuildProject` - build succeeded with no warnings or errors.
- Commands run: Xcode `RunAllTests` - 445 tests passed.
- Manual checks: Xcode issue navigator and build log contained no warnings or errors.

## Deviations from Assessment

- The user superseded the assessment's full stale-interval sequence proposal. The evidence contract
  remains exactly two file references: last changed baseline and threshold-confirming refresh.
- `StatusRenderer` did not require modification because it already renders any `.pair` in order.
- Sequence-specific error and partial-capture tests proposed by the assessment were not applicable
  after retaining the two-reference contract.
- `ValidationSession+Reporting.swift` and `ReportMarkdownTests.swift` were added to the change scope
  because report regeneration otherwise recomputed consecutive evidence and lost the baseline.

## Follow-ups

- Run `/speckit-bug-test slug=refresh-interval-stale-warning` for the independent verification report.

# Feature 003 — Reliable Monitoring and Evidence (PLANNED, not implemented)

Planned 2026-06-14. Artifacts: `specs/003-monitoring-evidence/{plan,research,data-model,quickstart}.md`
+ `contracts/{cli-interface,terminal-output,evidence-and-ids,report-format}.md`. Builds on
`mem:implementation-progress` (the 001/002 codebase). Ships **0.3.0**.

## Scope (output/reporting hardening only — NO validation change)
US1 evidence (P1/MVP) → US2 clutter-free monotonic heartbeat → US3 meaningful IDs → US4 default-all
selection → US5 pretty JSON files. Segment/bandwidth audit still OUT.

## FROZEN (FR-001/002, do not touch)
JSON report **schema/fields/values incl. `playlists[].id`**; rule set/rule IDs/finding catalog; exit
codes 0/1/2/3/130. Permitted structured-report changes ONLY: pretty-print whitespace + artifact-index
path *values* (FR-029). **No new dependency, project, or layer.** Core stays Foundation-only.

## Binding design decisions (research.md D1–D12)
- **D1/D2 Evidence = presentation join, NOT a schema field.** `Finding` already has `resource: URL` +
  `refreshIndex: Int?`; archive `IndexEntry{requestId,url,bodyPath,metaPath}`. Pure `EvidenceResolver`
  (new `Session/EvidenceResolver.swift`) → `.single`/`.pair`(continuity)/`.unavailable(id)`. **Join on
  URL, never `playlists[].id`.** Whole-file evidence only (no line/segment locus).
- **D3 ID scheme** = rework `AliasRegistry` IN PLACE (`Session/PlaylistAlias.swift`, keep public API):
  master / `<height>p_<codecs>` (drop `video-` prefix, append codecs) / `audio_<slug(LANGUAGE)>`
  (+`_<slug(NAME)>` on collision) / `subs_<…>` / `iframe_<height>p`; codecs = each CODECS entry trimmed
  to fourCC (drop from first `.`) joined by `-`; slug=lowercase+nonalnum→`_`; `_` reserved separator;
  dedup numeric suffix; role+ordinal fallback. Charset `[a-z0-9_-]` (fs-safe). ONE registry owned by
  the session.
- **D4 `SnapshotID`** (new pure file): `<id>_<n>` 0-based per-playlist index. Indexed form = continuity
  operands/single findings/verbose traces/per-refresh line/archive filename; bare `<id>` = roster/
  legend/heartbeat/ID assignment.
- **D6 Archive rename (FR-029):** `SessionArchive.store` filename `%06d` → `<id>_<n>.m3u8` +
  `<id>_<n>.meta.json`; pass the REAL registry `<id>` as `playlistID` (today caller passes
  `master`/`<role>-<i>`/`media` in `ValidationSession+Reporting.swift`).
- **D7 Monotonic heartbeat (root cause):** each `monitorPlaylist` emits `.activity` with its OWN
  per-playlist `refreshes` → displayed number bounces. Fix: session-wide monotonic counter under the
  `ValidationSession` actor; add field to `ActivityProgress`; heartbeat shows
  `<id> · refresh <sessionTotal> · <elapsed>` (SC-004 = total, not per-playlist index).
- **D8 Stray-key resilience (root cause):** terminal in cooked/echo mode → Enter echoes newline,
  scrolls in-place `\r…\u{1B}[K` region. Fix: CLI-only `LiveInputGuard` (new) clears termios
  `ECHO`/`ICANON` during live TTY monitoring, restores on every exit path (defer). Reuse
  `PlaylistChecklist` termios pattern. TTY-gated.
- **D9 Verbose tier:** `SessionEvent` (in `Session/SessionConfig.swift`) lacks trace cases. Add ADDITIVE
  `.rosterReady([RosterEntry])` (normal+), `.refreshCompleted(playlistID:index:errors:warnings:)`
  (normal+ per-refresh status line), `.trace(TraceEvent)` (verbose). New pure `Output/TraceFormatter`
  renders category-prefixed ID-based lines. CLI gates by `Verbosity` per the Output message catalog.
- **D10 Pretty JSON (CRITICAL):** `StatusRenderer.renderFinding` json branch uses compact
  `Finding.jsonEncoder` → THAT is the `--json` NDJSON path; do NOT flip it. Add SEPARATE
  `Finding.prettyJSONEncoder` (`+.prettyPrinted`) for FILES (report `buildJSON` + meta sidecars). Stream
  stays compact (FR-028). `.sortedKeys` already stable.
- **D11 Selection:** remove `--all` `@Flag` (→ unknown, exit 2); add `--preselect <pattern>` `@Option`
  (former `--select` pattern role); repurpose `--select` to a `@Flag` (interactive checklist, non-TTY →
  all + notice); `--select`+`--preselect` → exit 2; default = all, no prompt even on TTY. Rewire
  `SelectionPromptPolicy.from(...)` to key off `--select` flag.
- **D12 Version 0.3.0** (`MARKETING_VERSION`): pre-1.0 breaking change as minor + migration notes; lone
  Constitution-Check deviation (plan Complexity Tracking). Constitution V literal MAJOR declined.

## SC-003 bug to fix
Current `renderFinding` non-json branch prints `finding.resource.absoluteString` = RAW URL → must
become ID + evidence form (`SEVERITY <id>_<n> <msg> · evidence: playlists/<id>/<id>_<n>.m3u8`).

## Key edit points (current tree)
Core: `Session/PlaylistAlias.swift` (rework), new `Session/{SnapshotID,EvidenceResolver}.swift`, new
`Output/TraceFormatter.swift`, `Session/SessionConfig.swift` (events + ActivityProgress field),
`Session/SessionReportBuilder.swift` (md evidence spans + pretty buildJSON), `Validation/Finding.swift`
(add prettyJSONEncoder), `Archive/SessionArchive.swift` (filename), `ValidationSession{,+Reporting,
+Monitoring}.swift` (own registry, pass id, monotonic counter, emit events). CLI:
`ValistreamCommand.swift` (flags), `StatusRenderer.swift` (finding/roster/per-refresh/trace),
`ProgressView.swift` (heartbeat number), new `LiveInputGuard.swift`. Bump xcodeproj MARKETING_VERSION.

## Next: `/speckit-tasks` then `/speckit-analyze`.

# Feature 004 — Readable Output and Onboarding (PLANNED, not implemented)

Planned 2026-06-15. Ships **0.4.0**. Artifacts: `specs/004-output-readability/{plan,research,data-model,
quickstart}.md` + `contracts/{terminal-output,report-format,readme,compatibility}.md`. Builds on
`mem:implementation-progress` (001/002/003 codebase). See `mem:feature-004-spec`,
`mem:feature-004-acceptance-inputs`.

## Scope — PRESENTATION ONLY (no validation/schema/exit change)
Refine the EXISTING output layer (features 002/003 already shipped color/verbosity). FROZEN (FR-002/028):
validation results, rule/finding/playlist/snapshot IDs, evidence resolution, JSON report schema v1,
`.meta.json`, `FindingsLog` JSONL, `--json` stream, selection, exit codes 0/1/2/3/130.

## Existing infra to REUSE (confirmed by inspection)
- `Output/TerminalOutputMode.swift` — `colorEnabled = isTTY && !NO_COLOR && !--no-color && TERM!=dumb`,
  carries `verbosity` (.quiet/.normal/.verbose).
- CLI `TerminalWriter.swift` — Rainbow styling; has formatFinding/writeStatus/writeBlankLine/styledLine.
- `Output/ProgressFormatter.swift` (heartbeat text, no ANSI), `Output/TraceFormatter.swift` (verbose),
  CLI `ProgressView.swift` (`\r\u{1B}[K` transient), `StatusRenderer.swift`.
- `Rainbow` IS already a CLI dep (NOT new). Core stays Foundation-only.
- `Finding.observedAt: Date` already exists → reuse for finding timestamps.
- `PlaylistModel` rich: MasterPlaylist(variants/iFrameStreams/renditions/version/hasIndependentSegments),
  MediaPlaylist(targetDuration/mediaSequence/discontinuitySequence/segments/hasEndList/playlistType/
  isIFramesOnly/version/hasIndependentSegments/hasEncryptionKeys), VariantStream(bandwidth/averageBandwidth/
  resolution/frameRate/codecs/groupIDs), SegmentRef(duration/byteRange/hasDiscontinuity/programDateTime).
- `SessionEvent` cases: stateChanged/streamClassified/finding/monitorStateChanged/activity/
  sessionFolderResolved/rosterReady/refreshCompleted/trace. `StreamClassifier` exists (live/event/VOD).
- Version currently 0.3.0 (`MARKETING_VERSION` in pbxproj all configs + `CommandConfiguration.version`).
- Coverage NOW enabled in `Valistream/TestPlans/Valistream.xctestplan` (codeCoverage: Valistream +
  ValistreamCore) — user enabled it; read via `xcrun xccov view --report --json <.xcresult>`.

## Binding design decisions (research.md D1–D15)
- **D1 timestamps**: stamp every event at OCCURRENCE inside ValidationSession via injected `now` clock;
  carry via `TimestampedEvent { at: Date; event: SessionEvent }` envelope (case shapes unchanged, machine
  streams untouched). NEVER stamp at render time (FR-008c/025e/SC-003c).
- **D2 formatters** (new `Output/TimestampFormatter.swift`): terminal `[HH:mm:ss.SSS]` 24h LOCAL ms;
  report ISO-8601 LOCAL with ms + numeric UTC offset.
- **D3 one persistent result/refresh** (FR-008/SC-002): collapse duplicate stage msgs; detail → verbose
  trace; heartbeat excluded.
- **D4 roles + whole-line tint** (new `Output/PresentationRole.swift`): roles heading/identifier/success/
  progress/metadata/warning/error/evidencePath/summary; result+finding lines tinted WHOLE-LINE by severity
  (green/yellow/red), structural lines token-scoped. Palette = 8/16 ANSI only (no 256/truecolor).
- **D5 markers** (FR-013): monochrome Unicode `✓ OK`/`⚠ WARN`/`✗ ERROR` colored by severity; ASCII
  fallback `[OK]/[WARN]/[ERR]`. Add `GlyphStyle` (.unicode/.ascii) to TerminalOutputMode from LANG/LC_*
  UTF-8 detection (independent of colorEnabled). NO emoji in terminal.
- **D6 blank-line grammar** (FR-004/005/017j + USER DIRECTIVE): block taxonomy sessionSetup/roster/
  playlistInformation/refreshResult/lifecycleNotice/findingGroup/summary; EXACTLY ONE blank between
  adjacent blocks, NONE within; refresh result+findings+evidence = one contiguous block; collapse multiple
  blanks; no leading/trailing blanks; DISABLED for `--json` (FR-028). Implement via block-buffering writer.
- **D7 playlist info block** (FR-017a–j): new `Playlist/PlaylistInformation.swift` (MasterInfo/MediaInfo
  pure builder from PlaylistModel) + new `SessionEvent.playlistInformation(...)` emitted ONCE per playlist
  at first load; render normal+verbose terminal + markdown (identical fields FR-017c); QUIET omits. Segment
  duration stats (median, min–max) from FIRST snapshot only (FR-017d). Media block shows only own declared
  facts (FR-017g). Missing → `Unknown` vs `Not declared`; multi → list or `Mixed` (FR-017h).
- **D8 protection** (FR-017b): ADDITIVE read-only metadata on PlaylistModel — expose declared EXT-X-KEY
  METHOD+KEYFORMAT (media) + EXT-X-SESSION-KEY (master); new `Playlist/PlaylistProtection.swift` classify →
  None / Encrypted (AES-128) / DRM(<keyformat>). NO validation/rule/schema change. (Only non-presentation
  touch; justified by FR-017b/e/f.)
- **D9 incident timeline** (FR-025c–h): new `Session/IncidentTimeline.swift` (TimelineEntry/TimelineKind);
  warnings/errors/op-failures/evidence-capture-failures/shutdown/lifecycle; EXCLUDE routine refreshes;
  finding entries COMPACT + LINK to severity-grouped finding (no duplication SC-008b); order by (at,
  sequence) with monotonic `timelineSequence` tiebreak (FR-025g/SC-008c).
- **D10 lifecycle** (FR-025c): new `Session/PlaylistLifecycleEvent.swift` cases unavailable/recovered/
  added/removed/identityChanged; unavailable/recovered from monitorStateChanged/staleness; added/removed/
  identityChanged from roster diffs; new `SessionEvent.playlistLifecycle(...)`.
- **D11 markdown report** (FR-025/026/027/027a): outcome-first; section order Summary→Incident Timeline→
  Findings(errors→warnings→info)→Playlist Information→Legend→Session Details; GitHub callouts
  `> [!WARNING]`/`[!CAUTION]` + emoji icons (REPORT ONLY), degrade to blockquote+text; NO badges/HTML in
  report (badges README-only).
- **D12 README** (FR-029–037, FR-029a): full GitHub structure; badges license/release(0.4.0)/platform-swift/
  coverage; primary install = prebuilt `valistream-cli.zip` from GitHub Releases, secondary = source build,
  unpublished channels marked unsupported; quick-start uses VERIFIED public credential-free HLS stream;
  plain-text examples only (no screenshots/GIFs/casts); sanitized inputs.
- **D13 version**: bump MARKETING_VERSION (all pbxproj configs) + CommandConfiguration.version → 0.4.0.
- **D14 compatibility guards** (FR-002/028/SC-011): reuse 003 guards (ReportJSONSchemaTests/RuleEngine/
  conformance/exit codes) + new tests: `--json` structurally unchanged (no ts/blanks/ANSI), normal-vs-
  verbose equivalence.
- **D15 coverage** (USER DIRECTIVE): source = Valistream.xctestplan codeCoverage → `xcrun xccov`; README
  badge reflects current measured value or omitted (no stale).

## Target → filesystem paths (USER DIRECTIVE: full paths incl. workspace folder)
- Core sources: `Valistream/ValistreamCore/Sources/ValistreamCore/{Output,Playlist,Session}/`
- Core tests: `Valistream/ValistreamCore/Tests/ValistreamCoreTests/`
- CLI tool: `Valistream/Valistream/Valistream/` (TRIPLE Valistream)
- Integration tests: `Valistream/Valistream/ValistreamIntegrationTests/` (DOUBLED workspace folder)
- README at repo root; pbxproj `Valistream/Valistream/Valistream.xcodeproj/project.pbxproj`.

## Constitution Check (v1.1.0) = PASS, Complexity Tracking EMPTY
Spec-First ✓ (19 clarifications resolved); Test-First ✓ (tests before impl, no waiver); YAGNI ✓ (reuse layer
+ Rainbow, only additive key metadata); Independent increments ✓ (P1–P4, P1=MVP); Versioning ✓ (0.3.0→0.4.0
pre-1.0 MINOR + migration note, machine contracts frozen).

## New/changed files (plan Project Structure)
NEW Core: Output/{TimestampFormatter,PresentationRole,PlaylistInfoFormatter}.swift,
Playlist/{PlaylistInformation,PlaylistProtection}.swift, Session/{PlaylistLifecycleEvent,IncidentTimeline}.swift.
EXTEND Core: Output/TerminalOutputMode (GlyphStyle), Playlist/{PlaylistModel,PlaylistBuilder} (additive key
meta), Session/{SessionConfig (events+TimestampedEvent), SessionReportBuilder, ValidationSession(+Monitoring/
+Reporting)}. EXTEND CLI: ValistreamCommand (0.4.0, GlyphStyle), StatusRenderer, TerminalWriter; reuse
ProgressView/LiveInputGuard/PlaylistChecklist/PromptberrySelection. REWRITE README.md; bump pbxproj.

## Next: `/speckit-tasks` → `/speckit-analyze` → `/speckit-implement`.

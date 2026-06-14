# Feature Specification: Reliable Monitoring and Evidence

**Feature Branch**: `main` (no dedicated feature branch — git extension not installed)

**Created**: 2026-06-13

**Status**: Draft

**Input**: User description: "Polishing. Need to make valistream tool stable, reliable and useful. In this
feature: update playlist IDs to easier differentiate between video renditions — ID can be
`variant_<resolution>_<codecs>`; update master playlist ID to `master`; change stdout wording to be
more descriptive; add useful `--verbose` stdout (currently almost same as standard); use playlist IDs
in stdout as well, print when session starts, refer to IDs; investigate why stdout live monitoring
status is flaky (number of refreshes jumps back and forth after several Enter presses); IMPORTANT —
when ERROR or WARN happens, stdout and report MUST include 'evidence': the exact file where the
error/warn is seen, and if a continuity issue, two files must be referenced; start monitoring for
`--all` by default, remove the `--all` option, rename `--select` → `--preselect`, and make `--select`
indicate that the checklist prompt is needed; pretty-format all generated JSONs. Bottom-line idea:
rework stdout to remove clutter (especially when long URLs are passed) and make it a real heartbeat
monitoring tool with concrete evidence when something goes wrong; plus update the report to carry
maximum usefulness with evidence to make troubleshooting and reporting issues to the backend team
faster." (Clarification from user: "playlist ID" and "alias" are used interchangeably — both mean the
short, human-readable label shown in output and report in place of full URLs.)

## Clarifications

### Session 2026-06-14

- Q: How is `<codecs>` rendered in a video rendition's `<height>p_<codecs>` ID when the `CODECS` attribute lists multiple codecs (e.g. video + audio)? → A: Join all advertised codecs, each trimmed to its sample-entry/fourCC (profile/level dropped), with `-` (e.g. `avc1.640028,mp4a.40.2` → `avc1-mp4a`); the `_` field separator is preserved.
- Q: For `audio_<lang|name>` / `subs_<lang|name>` IDs, which source field wins and how are same-language tracks disambiguated? → A: Prefer slugified `LANGUAGE` (e.g. `audio_en`); on a same-language collision append the slugified `NAME` (e.g. `audio_en_commentary`); use `NAME` alone when `LANGUAGE` is absent; fall back to role+ordinal when both are missing. Slug = lowercased, non-alphanumeric collapsed to `_`.
- Q: This release makes a backward-incompatible CLI change; what version does it ship as, given Constitution V says breaking → MAJOR but the tool is pre-1.0? → A: `0.3.0` (minor bump). Under SemVer the pre-1.0 (0.y.z) series carries no stable-API promise, which satisfies the constitution's versioning intent; migration notes remain required (FR-003). A literal MAJOR (`1.0.0`) reading would require a separate constitution amendment and is declined here.
- Q: At `--quiet`, what stdout is shown? → A: Errors + warnings (each with its evidence path), evidence-unavailable notices, and fatal operational errors, plus the final summary (finding counts + report/artifact paths). Quiet suppresses the roster, heartbeat, progress, per-refresh activity, and all INFO/OK lines. IDs stay self-describing and evidence paths open directly; the full URL→ID legend lives in the report whose path the summary prints.
- Q: At the default (normal) level, which findings/severities print? → A: ERROR + WARN (each with evidence), key INFO milestones (session start, selection summary, shutdown, final summary), and the live heartbeat. Granular per-rule pass/fail and standalone per-playlist `OK` detail are verbose-only — the per-refresh roll-up status defined in the next clarification is what shows at default — so the default surface stays a calm heartbeat where problems stand out.
- Q: How are refreshes rendered at the default level, and what does each refresh line show? → A: Option B plus a per-refresh status summary. At default each refresh prints a discrete line (scrolls on a TTY in addition to the in-place heartbeat; one plain line per refresh when piped) ending with a status summary — `OK` when the refresh produced no findings, otherwise the counts `x WARN, y ERROR`. The individual WARN and ERROR messages (each with its evidence) print indented beneath their refresh's line. Per-request detail and per-rule outcomes (including per-rule `OK`) stay verbose-only; quiet shows neither refresh lines nor heartbeat (its errors and warnings print flat, per the quiet rule above).
- Q: What does `--verbose` show? → A: Maximum descriptiveness — verbose traces every action the tool performs as a descriptive, category-prefixed, ID-based line (e.g. `Fetch: requesting playlist <ID>`; `Fetch: playlist <ID> HTTP 200; 25ms; 1.3 kB`; `Validation: playlist <ID> — OK`; `Stored: playlist <ID> → <file> in playlists/`), covering at least fetch intent, fetch result (status/duration/bytes), per-playlist and per-rule validation outcomes including `OK`, archive writes, refresh scheduling/cadence, and continuity comparisons. Verbose stays ID-based; full URLs remain confined to the roster, so SC-003 holds at every tier. Full catalog: see the **Output message catalog** table under Requirements.
- Q: Video-rendition ID `1080p_avc1` vs the frozen `variant_1920x1080_avc1` — which is canonical? → A: Adopt `1080p_avc1`. Video IDs are `<height>p_<codecs>` — pixel height + `p`, no `variant_` prefix, codecs joined by `-` (e.g. `1080p_avc1`, `1080p_avc1-mp4a`). Master stays `master`; audio/subtitle/I-frame keep their role prefixes (`audio_en`, `subs_en`, `iframe_<height>p`). Supersedes the earlier `variant_<resolution>_<codecs>` form; same-height collisions resolved by the dedup suffix (FR-019).
- Q: What does the continuity `_<index>` count, and where does `<id>_<n>` appear? → A: 0-based per-playlist refresh index (first fetch `_0`, +1 each refresh). The indexed form `<id>_<n>` denotes a specific snapshot and is used wherever a particular refresh is meant: continuity findings (both operands, e.g. `1080p_avc1_4`↔`1080p_avc1_5`), single-snapshot findings, every `--verbose` action/trace line (e.g. `Fetch: playlist 1080p_avc1_5 …`, `Stored: …`, `Validation: …`, `Compare: …`), and the per-refresh status line, plus the archive filename. The bare `<id>` is used for identity/display: roster, legend, in-place heartbeat, ID assignment. VOD/single-fetch playlists only have `_0`.
- Q: How are archived playlist snapshots named, given 001 uses `playlists/<id>/NNNNNN.m3u8`? → A: `playlists/<id>/<id>_<n>.m3u8` with a matching `<id>_<n>.meta.json` sidecar (e.g. `playlists/1080p_avc1/1080p_avc1_5.m3u8`) — keep the per-playlist subdir, but name the file with the snapshot label so an evidence file is self-identifying when attached to a ticket. Refines feature 001's archive layout; the structured report's schema stays frozen (FR-002), only the artifact-index path values reflect the new names.
- Q: How is each evidence reference rendered in the human-readable Markdown report? → A: As an inline code span containing the relative archive path only (e.g. `playlists/1080p_avc1/1080p_avc1_5.m3u8`) — matching the terminal form exactly; not a Markdown link, so it stays copy-pasteable and viewer-agnostic.
- Q: In the evidence-unavailable notice, how is the attempted resource named? → A: Always by the playlist's ID/label, never a raw URL; when a failure prevented normal ID assignment a deterministic placeholder is used (master → `master`; otherwise the role-plus-ordinal fallback of FR-020), so SC-003 (zero raw URLs in the body) holds unconditionally.
- Q: Does an evidence reference pinpoint a locus inside the file (line/segment), or name the whole file only? → A: Whole archived snapshot file only — no in-file line number or segment/tag pointer. Matches the user's "exact file" brief and the two-file continuity model; the self-identifying filename is the proof. (A locus would be new derived data outside FR-001's frozen finding catalog.)

## User Scenarios & Testing *(mandatory)*

This feature does not add validation capabilities. It hardens the **output and reporting** of the
existing validator (features 001 and 002) so that the tool reads like a calm heartbeat monitor and,
the moment something is wrong, hands the operator the exact on-disk evidence needed to act and to
escalate to a backend team. Stories are sliced so each is an independently shippable improvement,
ordered by how much trust and usefulness each unlocks.

### User Story 1 - Concrete Evidence When Something Goes Wrong (Priority: P1)

An engineer is watching a session (or reading its report afterward) and sees an error or warning.
Instead of a message that merely *names* the problem, every error and warning is accompanied by
**evidence**: the exact archived file on disk that the finding was observed in. For a problem that is
established by comparing two consecutive refreshes of the same playlist (a continuity issue), the tool
references **both** files — the two snapshots whose comparison produced the finding. The engineer can
open the named file(s) immediately, confirm the issue with their own eyes, and attach those exact
files when reporting the problem to the backend team — no guessing which fetch, which refresh, or
which line.

**Why this priority**: This is the single change that turns the tool from "something is wrong
somewhere" into "here is the proof, in this file." It is the explicitly flagged, highest-value
improvement: it makes both troubleshooting and backend escalation dramatically faster, and it is
useful on its own regardless of any cosmetic change.

**Independent Test**: Run a session against a stream known to produce at least one error, one warning,
and one continuity finding. Confirm that each error and warning printed to the terminal and written to
the report names an evidence file that exists on disk and contains the relevant content, and that the
continuity finding names exactly two consecutive snapshot files.

**Acceptance Scenarios**:

1. **Given** a validation that produces an error tied to a single playlist response, **When** the
   error is shown on the terminal and written to the report, **Then** both include a reference to the
   exact archived file the error was observed in, openable by the reader.
2. **Given** a validation that produces a warning, **When** it is shown and written, **Then** it
   carries the same kind of evidence file reference as an error.
3. **Given** a continuity finding derived from comparing two consecutive refreshes of one playlist,
   **When** it is shown and written, **Then** it references both consecutive archived files (the
   before and after snapshots).
4. **Given** a finding whose evidence file could not be archived (e.g., the fetch that would have
   produced it failed), **When** the finding is reported, **Then** the tool states this explicitly
   (names the attempted resource and that no body was captured) rather than printing a missing or
   dangling path.
5. **Given** the structured (machine-readable) report, **When** a consumer inspects any error or
   warning, **Then** the evidence file(s) for that finding are recoverable from the report using its
   existing fields, with no change to the report's frozen schema.

---

### User Story 2 - A Clutter-Free Heartbeat You Can Read at a Glance (Priority: P2)

An operator runs the tool with long playlist URLs and wants the terminal to read like a steady,
legible heartbeat rather than a wall of repeated URLs and vague status lines. At session start the
tool prints a short roster: each playlist's human-readable ID alongside its full URL and role. From
then on, every message refers to playlists by their short ID, so the running output stays compact even
when the inputs are enormous URLs. Wording is descriptive ("refreshing `1080p_avc1`,
refresh 5") instead of terse or ambiguous. During live monitoring the status is a stable in-place
heartbeat whose refresh count only ever moves forward — pressing Enter a few times (or other stray
keystrokes) never makes the count jump backward or scramble the display.

**Why this priority**: This is the bottom-line goal — making the tool a real, trustworthy monitoring
surface. A clean, ID-based, descriptive, rock-steady heartbeat is what makes long sessions watchable
and the evidence from US1 easy to locate. It builds on the responsive session loop and live status
from feature 002.

**Independent Test**: Run a session with very long playlist URLs and confirm the start-of-session
roster prints each ID with its full URL/role, that no full URL is repeated in the body afterward, and
that wording names the current action and playlist ID. For the heartbeat: start a live session, let
several refreshes occur, press Enter many times, and confirm the displayed refresh count never
decreases and the status region never becomes corrupted.

**Acceptance Scenarios**:

1. **Given** a session with multiple playlists, **When** it starts, **Then** before fetching begins
   the tool prints a roster mapping each playlist's short ID to its full URL and role.
2. **Given** the session is running, **When** any status or finding message is printed, **Then** it
   refers to playlists by short ID and does not repeat the full URL inline.
3. **Given** a long-running live session, **When** refreshes occur over time, **Then** the in-place
   heartbeat shows a refresh count that is monotonic (never decreases or jumps backward) and matches
   the actual number of refreshes performed.
4. **Given** a live session, **When** the user presses Enter repeatedly or sends other stray
   keystrokes, **Then** the status display stays intact and the refresh count remains correct and
   monotonic.
5. **Given** the same session, **When** it is run at `--verbose`, **Then** the output contains
   substantially more, distinct diagnostic detail than the normal level (not a near-duplicate of it).

---

### User Story 3 - Meaningful, Differentiated Playlist IDs (Priority: P3)

A user looking at the roster, the running output, or the report needs to tell renditions apart at a
glance. The master playlist is simply `master`. Each video rendition is identified by its
distinguishing attributes — `<height>p_<codecs>` (e.g. `1080p_avc1`) — so two renditions at the same resolution
but different codecs, or the same codec at different resolutions, are immediately distinguishable
rather than collapsing into a vague label. Audio, subtitle, and image (I-frame) playlists get
analogous role-based IDs. The same ID for a given playlist is used everywhere it appears (roster,
status, report body, legend) and stays the same across the whole session.

**Why this priority**: Meaningful IDs are what make the ID-based output of US1 and US2 actually
useful — you cannot refer to "the file for the 1080p AVC variant" if every variant looks the same.
It supersedes feature 002's coarser alias scheme and is independently demonstrable.

**Independent Test**: Run against a master playlist that advertises several video renditions differing
by resolution and codec, plus audio/subtitle/I-frame playlists. Confirm the master's ID is `master`,
each video rendition's ID follows `<height>p_<codecs>` and is unique, and audio/subtitle/
I-frame playlists get clear role-based IDs. Re-run and confirm the IDs are identical.

**Acceptance Scenarios**:

1. **Given** a master playlist, **When** IDs are assigned, **Then** the master's ID is exactly
   `master`.
2. **Given** several video renditions, **When** IDs are assigned, **Then** each is
   `<height>p_<codecs>` and renditions differing only by codec (or only by resolution)
   receive distinct IDs.
3. **Given** audio, subtitle, and I-frame playlists, **When** IDs are assigned, **Then** each gets a
   clear role-based ID distinct from the video renditions.
4. **Given** two playlists that would derive the same ID, **When** IDs are assigned, **Then** the
   collision is resolved deterministically (e.g., a numeric suffix) so every ID is unique within the
   session.
5. **Given** the same stream, **When** the tool is run twice, **Then** the assigned IDs are identical
   across runs, and within a run each playlist keeps its ID across every refresh and report update.
6. **Given** a playlist that lacks distinguishing attributes, **When** an ID is assigned, **Then** a
   documented deterministic fallback is used so the playlist still receives a unique, sensible ID.

---

### User Story 4 - Process Everything by Default, Prompt Only on Request (Priority: P4)

A user just wants to point the tool at a stream and have it validate every rendition, with no prompt
interrupting an automated run. By default the tool now processes all renditions — no flag required and
no selection prompt, even on an interactive terminal. When they *do* want to narrow the scope up front
for an unattended run, they pass `--preselect <pattern>`. When they want to pick interactively, they
pass `--select`, which brings up the multi-select checklist (everything pre-checked) so they can
deselect what they do not need.

**Why this priority**: This removes a default interruption and makes the common case (validate
everything) the zero-friction path, while keeping both unattended narrowing and interactive selection
available. It is a focused command-line change, independent of the output and evidence work.

**Independent Test**: Run with no selection flags and confirm all renditions are processed with no
prompt (including on a TTY). Run with `--preselect <pattern>` and confirm the subset is applied with
no prompt. Run with `--select` on a terminal and confirm the interactive checklist appears
pre-selected. Confirm `--all` is no longer accepted.

**Acceptance Scenarios**:

1. **Given** no selection flags, **When** a session starts (even on an interactive terminal), **Then**
   all renditions are processed and no selection prompt is shown.
2. **Given** the `--all` option, **When** it is passed, **Then** it is rejected as an unknown option
   (it has been removed because its behavior is now the default).
3. **Given** `--preselect <pattern>`, **When** a session starts, **Then** the matching subset is
   processed with no prompt, preserving unattended/scriptable operation.
4. **Given** `--select` on an interactive terminal, **When** the selection step is reached, **Then**
   the multi-select checklist is shown with all renditions pre-selected.
5. **Given** `--select` and `--preselect` together, **When** options are parsed, **Then** the tool
   reports a usage error (exit 2). **Given** `--select` without an interactive terminal, **When** the
   session starts, **Then** the tool falls back to the default (all) and says so, rather than failing.

---

### User Story 5 - Readable, Pretty-Printed JSON Artifacts (Priority: P5)

A user (or a teammate, or a script author) opens a JSON file the tool wrote — the structured report or
an artifact's metadata sidecar — and finds it cleanly indented and human-skimmable rather than a
single dense line. Every JSON file written to disk is pretty-printed with stable key ordering. The
machine-readable status stream (the line-delimited `--json` output) is deliberately left as one
compact object per line, so existing line-by-line consumers keep working.

**Why this priority**: Pretty-printing is a small, low-risk readability win that helps anyone who opens
the artifacts directly. It is the most optional improvement, hence lowest priority, and is
independently shippable.

**Independent Test**: Run a session and open the structured report and an artifact metadata sidecar;
confirm both are multi-line and indented and parse to the same content as before. Capture the `--json`
status stream and confirm it remains exactly one JSON object per line.

**Acceptance Scenarios**:

1. **Given** any JSON file the tool writes to disk, **When** it is opened, **Then** it is indented and
   multi-line with consistent, stable key ordering.
2. **Given** the structured report, **When** it is pretty-printed, **Then** its logical content is
   unchanged and it still validates against the frozen feature 001 schema.
3. **Given** the line-delimited `--json` status stream, **When** it is captured, **Then** it remains
   one compact JSON object per line (not pretty-printed), so line-delimited consumers are unaffected.

---

### Edge Cases

- **Two renditions with identical resolution and codecs**: their IDs would collide and are
  de-duplicated deterministically (e.g., numeric suffix), so every ID stays unique within the session.
- **Rendition missing resolution or codec attributes**: a documented deterministic fallback ID is used
  (e.g., role plus ordinal) so the playlist still gets a unique, sensible ID.
- **Evidence file never archived** (the producing fetch failed): the finding states that no body was
  captured and names the attempted resource by its ID/label (never a raw URL), instead of pointing at
  a non-existent file.
- **Continuity finding where only one of the two snapshots was archived**: the available file is
  referenced and the missing one is clearly noted.
- **Very long URLs in the input**: full URLs appear only in the start-of-session roster and the report
  legend; the running body and report findings refer to IDs, so length never clutters the stream.
- **Very long codec strings**: each advertised codec is trimmed to its sample-entry/fourCC
  (profile/level dropped), so IDs stay readable while the resolution plus codecs keep them unique.
- **Stray keystrokes during live monitoring** (Enter, arrows, etc.): never corrupt the in-place status
  region nor move the refresh count backward.
- **Non-interactive run with `--select`**: a prompt is impossible, so the tool falls back to the
  documented default (all) and says so rather than hanging or erroring.
- **Output redirected to a file/pipe, or `NO_COLOR`/`--no-color`**: evidence references and IDs are
  still fully present in plain text; no color or cursor control is emitted.
- **Pretty-printed report grows in size**: larger byte size is acceptable; logical content and schema
  validity are unchanged.

## Requirements *(mandatory)*

### Functional Requirements

#### Cross-cutting

- **FR-001**: This feature MUST NOT change the validation rule set, the catalog of detected findings,
  or the exit-code contract established by feature 001; existing automation built on those MUST
  continue to work unchanged.
- **FR-002**: The structured (machine-readable) report MUST continue to validate against feature 001's
  frozen schema — no fields added, removed, renamed, or retyped, and no field *values* repurposed
  (including `playlists[].id`). The only change to the structured report permitted by this feature is
  whitespace/indentation from pretty-printing (FR-026–027).
- **FR-003**: Discoverable help and version output MUST document every option, including the changed
  selection options (FR-021–025). Backward-incompatible command-line changes MUST be called out as
  breaking, with migration guidance from the previous option names/behavior.

#### Evidence for every problem (US1)

- **FR-004**: Every ERROR and WARNING printed to the terminal MUST include an **evidence** reference:
  the exact archived file on disk in which the issue was observed.
- **FR-005**: Every ERROR and WARNING written to the human-readable report MUST include the same
  evidence file reference(s) as the terminal output, each rendered as an inline code span containing
  the relative archive path (e.g. `playlists/1080p_avc1/1080p_avc1_5.m3u8`) — not a Markdown link — so
  it matches the terminal form and stays copy-pasteable and viewer-agnostic.
- **FR-006**: A finding established by comparing two consecutive refreshes of a playlist (a continuity
  finding) MUST reference **both** archived files — the two consecutive snapshots whose comparison
  produced the finding — and MUST label them by their indexed snapshot IDs `<id>_<n-1>` and `<id>_<n>`
  (FR-018a).
- **FR-007**: Each evidence reference MUST let the reader open the named file directly, expressed as a
  path within the session's output folder (the archive location already produced by the tool) — e.g.
  `playlists/1080p_avc1/1080p_avc1_5.m3u8` (FR-029).
- **FR-008**: The evidence file(s) for any ERROR or WARNING MUST be recoverable from the structured
  report using its existing fields (the artifact index together with each finding's resource and
  refresh information), so that no change to the frozen schema (FR-002) is required.
- **FR-009**: When an expected evidence file is unavailable (e.g., the producing fetch failed), the
  tool MUST state this explicitly — naming the attempted resource **by its playlist ID/label (never a
  raw URL)** and that no body was captured — rather than emit a missing or dangling path. When a
  failure prevented normal ID assignment, a deterministic placeholder MUST be used (the master is
  `master`; otherwise the role-plus-ordinal fallback of FR-020), so SC-003 holds unconditionally.
- **FR-029**: Archived playlist snapshots MUST be written as `playlists/<id>/<id>_<n>.m3u8` with a
  matching `<id>_<n>.meta.json` sidecar, where `<id>` is the playlist's ID and `<n>` its 0-based
  per-playlist refresh index (FR-018a). The file name therefore equals the snapshot label used in
  findings and traces, so any evidence file is self-identifying. This refines feature 001's archive
  layout (`playlists/<id>/NNNNNN.m3u8`); the structured report's schema is unchanged (FR-002) — only
  the artifact-index path *values* reflect the new names.

#### Clutter-free, descriptive, steady heartbeat output (US2)

- **FR-010**: Terminal messages MUST use descriptive, human wording that names what the tool is doing
  and which playlist (by ID) it concerns, replacing terse or ambiguous phrasing.
- **FR-011**: At session start, before fetching begins, the tool MUST print a **roster** mapping each
  discovered playlist's short ID to its full URL and role/attributes.
- **FR-012**: After the roster, the running terminal output and the report body MUST refer to playlists
  by short ID and MUST NOT repeat full playlist URLs inline; full URLs appear only in the roster and in
  the report's legend.
- **FR-013**: During live monitoring the tool MUST present a stable, in-place heartbeat (current
  activity, refresh count, elapsed time) whose refresh count is **monotonic** — it MUST NOT decrease or
  jump backward — and MUST accurately reflect the number of refreshes performed.
- **FR-014**: Stray user input during live monitoring (e.g., repeated Enter presses or other
  keystrokes) MUST NOT corrupt the status display nor cause the refresh count to move backward or be
  miscounted.
- **FR-015**: The `--verbose` level MUST add substantive, distinct diagnostic detail beyond the normal
  level (for example per-request status/timings/sizes, per-rule outcomes, and refresh-cadence detail);
  normal and verbose output MUST be clearly and noticeably different. Verbosity MUST NOT affect the
  report files or exit codes (FR-001).
- **FR-015a**: Stdout messages MUST follow the verbosity-tier assignment in the **Output message
  catalog** below. Higher tiers are supersets of lower ones (quiet ⊆ normal ⊆ verbose); quiet and
  normal MUST NOT emit verbose-only action traces. Tier membership affects on-screen output only —
  never the report files or exit codes (FR-001).
- **FR-015b**: At `--verbose` the tool MUST trace **every** action it performs as a descriptive,
  category-prefixed line that refers to playlists by ID — at minimum: fetch intent, fetch result
  (HTTP status, duration, bytes), per-playlist and per-rule validation outcomes (including `OK`),
  archive writes (the stored file name), refresh scheduling/cadence, and continuity comparisons.
  Verbose output stays ID-based; full URLs remain confined to the roster, so SC-003 holds at every tier.

**Output message catalog** (✓ = emitted at that tier; `normal` also shows all `quiet` rows, `verbose`
shows all `normal` rows):

| Message | Example format | quiet | normal | verbose |
|---------|----------------|:-----:|:------:|:-------:|
| Version / help | `valistream <semver>` / usage text | on-demand | on-demand | on-demand |
| Fatal usage/IO error (stderr, exit 2) | `ERROR: --output …: not writable` | ✓ | ✓ | ✓ |
| Output folder announced (absolute) | `Output: /…/sessions/<id>/` | | ✓ | ✓ |
| Session roster (ID → URL + role) | `master   https://…/master.m3u8   (master)` | | ✓ | ✓ |
| Selection checklist (`--select` + TTY) | interactive multi-select | interactive | interactive | interactive |
| `--select` non-TTY fallback notice | `--select ignored (no TTY); processing all` | ✓ | ✓ | ✓ |
| Session-start milestone | `Monitoring session <id> — N playlists` | | ✓ | ✓ |
| In-place heartbeat (TTY) | `⠼ 1080p_avc1 · refresh 12 · 1m20s` | | ✓ | ✓ |
| Per-refresh status line | `1080p_avc1_12 — OK` · `1080p_avc1_12 — 2 WARN, 1 ERROR` | | ✓ | ✓ |
| ERROR finding (+ evidence) | `ERROR 1080p_avc1_5 <msg> · evidence: playlists/1080p_avc1/1080p_avc1_5.m3u8` | ✓ | ✓ | ✓ |
| WARN finding (+ evidence) | `WARN 1080p_avc1_5 <msg> · evidence: playlists/1080p_avc1/1080p_avc1_5.m3u8` | ✓ | ✓ | ✓ |
| Continuity finding (two files) | `WARN 1080p_avc1 discontinuity 1080p_avc1_4↔_5 · evidence: …/1080p_avc1_4.m3u8, …/1080p_avc1_5.m3u8` | ✓ | ✓ | ✓ |
| Evidence-unavailable notice | `WARN 1080p_avc1_5 — no body captured for <id>` (ID/label, never a URL) | ✓ | ✓ | ✓ |
| INFO milestone | `INFO selected 4 of 6 renditions` | | ✓ | ✓ |
| Fetch intent | `Fetch: requesting playlist 1080p_avc1_5` | | | ✓ |
| Fetch result | `Fetch: playlist 1080p_avc1_5 HTTP 200; 25ms; 1.3 kB` | | | ✓ |
| Validation outcome — per playlist | `Validation: playlist 1080p_avc1_5 — OK` | | | ✓ |
| Validation outcome — per rule | `Validation: 1080p_avc1_5 rule TARGETDURATION — OK` | | | ✓ |
| Archive write | `Stored: playlist 1080p_avc1_5 → playlists/1080p_avc1/1080p_avc1_5.m3u8` | | | ✓ |
| Refresh scheduling / cadence | `Refresh: 1080p_avc1 refresh 13 in 6s (drift +0.2s)` | | | ✓ |
| Continuity comparison trace | `Compare: 1080p_avc1_12↔_11 — continuous` | | | ✓ |
| Rendition lifecycle (added/dropped) | `INFO master added rendition 1080p_avc1` | | | ✓ |
| Shutdown notice | `Stopping… (Ctrl-C again to force)` | ✓ | ✓ | ✓ |
| Final summary (counts + paths) | `Done: 1 ERROR, 2 WARN — report …/report.md` | ✓ | ✓ | ✓ |

#### Meaningful playlist IDs (US3)

- **FR-016**: Each playlist MUST be assigned a short, human-readable ID (the label feature 002 calls an
  "alias") that is used consistently wherever the playlist is referenced in terminal output and the
  report body, in place of its full URL.
- **FR-017**: The master playlist's ID MUST be exactly `master`.
- **FR-018**: A video rendition's ID MUST follow `<height>p_<codecs>` (pixel height + `p`, then codecs; no `variant_` prefix — e.g. `1080p_avc1`), so renditions
  differing by resolution or by codec are distinguishable; audio, subtitle, and I-frame playlists MUST
  use analogous, clearly distinct role-based ID schemes. `<codecs>` MUST include every codec advertised
  in the rendition's `CODECS` attribute (e.g. video and audio), each trimmed to its sample-entry/fourCC
  identifier (profile/level detail dropped) and joined in advertised order by `-` (e.g. `avc1-mp4a`);
  the `_` field separator is reserved and MUST NOT appear inside a field value. Audio and subtitle IDs
  MUST derive from the slugified `LANGUAGE` (e.g. `audio_en`, `subs_en`); when multiple tracks share a
  language the slugified `NAME` MUST be appended to disambiguate (e.g. `audio_en_commentary`); `NAME`
  alone MUST be used when `LANGUAGE` is absent; and role+ordinal (FR-020) MUST be used when both are
  missing. (Slug = lowercased, non-alphanumeric collapsed to `_`.)
- **FR-018a**: A specific refresh snapshot MUST be identified by the indexed form `<id>_<n>`, where
  `<n>` is the 0-based per-playlist refresh index (first fetch `_0`). The indexed form MUST be used
  wherever a particular refresh is meant — continuity findings (citing both `<id>_<n-1>` and
  `<id>_<n>`), single-snapshot findings, every `--verbose` action/trace line, the per-refresh status
  line, and the archive file name (FR-029) — while the bare `<id>` is used for identity and display
  (roster, legend, in-place heartbeat, ID assignment).
- **FR-019**: IDs MUST be stable within a session (the same playlist keeps its ID across every refresh
  and report update), deterministic across runs of the same stream, and unique within the session
  (collisions de-duplicated deterministically).
- **FR-020**: When a playlist lacks the attributes needed to build its preferred ID, the tool MUST use
  a documented deterministic fallback (e.g., role plus ordinal) so every playlist still receives a
  unique, sensible ID.

#### Selection model (US4)

- **FR-021**: By default — with no selection flags — the tool MUST process all renditions without
  showing a selection prompt, including on an interactive terminal (this becomes the former `--all`
  behavior).
- **FR-022**: The `--all` option MUST be removed and MUST be rejected as an unknown option if supplied.
- **FR-023**: A `--preselect <pattern>` option MUST select a rendition subset up front without
  prompting (the behavior formerly provided by `--select <pattern>`), preserving unattended/scriptable
  operation.
- **FR-024**: A `--select` option MUST request the interactive multi-select checklist (all renditions
  pre-selected) so the user can choose a subset interactively.
- **FR-025**: `--select` and `--preselect` MUST be mutually exclusive (usage error, exit 2). `--select`
  on a non-interactive terminal (where no prompt is possible) MUST fall back to the default (all) and
  announce the fallback, rather than fail.

#### Pretty-printed JSON (US5)

- **FR-026**: Every JSON file the tool writes to disk (the structured report and any artifact metadata
  sidecars) MUST be pretty-printed: indented, multi-line, with stable, consistent key ordering.
- **FR-027**: Pretty-printing MUST NOT alter logical JSON content; the structured report MUST remain
  valid against feature 001's schema (FR-002).
- **FR-028**: The line-delimited machine-readable status stream (`--json`) MUST remain one compact JSON
  object per line (not pretty-printed), so line-delimited consumers are unaffected.

### Key Entities *(include if feature involves data)*

- **Playlist ID** *(the human-readable label feature 002 calls an "alias"; the user uses "ID" and
  "alias" interchangeably)*: a short, deterministic, session-unique, stable label that stands in for a
  full playlist URL throughout terminal output and the report body. Scheme: `master` for the master;
  `<height>p_<codecs>` for video renditions (e.g. `1080p_avc1`; `<codecs>` = every advertised codec trimmed to
  its fourCC, joined by `-`); analogous role-based forms for audio, subtitle,
  and I-frame playlists; deterministic fallback when attributes are missing. It is a presentation
  label and does not appear in the structured (JSON) report. A specific refresh is referenced by the
  indexed form `<id>_<n>` (0-based per-playlist refresh index), which also names its archived snapshot
  file (FR-018a, FR-029).
- **Evidence Reference**: the exact archived on-disk file(s) that constitute proof of a finding — one
  file for a single-snapshot finding, two consecutive snapshot files for a continuity finding —
  surfaced in terminal output and the report and recoverable from the structured report via its
  existing fields. Each file's name equals its snapshot label `<id>_<n>.m3u8` (FR-029), so it is
  self-identifying when opened or attached to a report. Evidence is whole-file only: it names the
  proof file(s), never an in-file line number or segment/tag locus.
- **Session Roster / Legend**: the mapping of each playlist ID to its full URL and role/attributes,
  printed once at session start (roster) and present in the report (legend), so all other output can
  refer to IDs without repeating URLs.
- **Heartbeat / Live Status**: the stable, in-place live-monitoring status region (activity, monotonic
  refresh count, elapsed time) that is resilient to stray user input.
- **Verbosity Level**: quiet / normal / verbose. Quiet = findings (errors/warnings, each with evidence)
  + evidence-unavailable notices + fatal errors + final summary only; normal adds the roster, session
  milestones, the in-place heartbeat, and a per-refresh status line (`OK` / `x WARN, y ERROR`) with the
  findings nested beneath; verbose adds a descriptive, ID-based trace of every action (fetch, validate,
  store, refresh, compare) — maximum descriptiveness. Affects on-screen output only, never report files
  or exit codes. See the **Output message catalog** (FR-015a) for the full tier assignment.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of ERROR and WARNING items — in both terminal output and the report — include at
  least one evidence file reference; 100% of continuity findings include exactly two consecutive
  evidence file references.
- **SC-002**: A reader can open the evidence file for any given error directly from the path shown,
  with no additional lookup, in under 15 seconds.
- **SC-003**: Outside the start-of-session roster and the report's legend, the terminal body and the
  report body contain zero raw playlist URLs — at every verbosity level, including `--verbose`, whose
  action trace stays ID-based.
- **SC-004**: Across a 30-minute live session that includes at least 20 stray Enter presses, the
  displayed refresh count is monotonic non-decreasing and equals the actual number of refreshes
  performed (zero backward jumps, zero miscounts).
- **SC-005**: `--verbose` output includes everything the normal level shows plus a descriptive trace
  line for every action — at least five categories absent at the normal level (fetch intent, fetch
  result, per-playlist/per-rule validation outcomes, archive writes, refresh-cadence, continuity
  comparisons) — so verbose is clearly not a near-copy of normal.
- **SC-006**: Every playlist ID is unique within a session and identical across repeated runs of the
  same stream; two video renditions that differ only by codec (or only by resolution) receive distinct
  IDs.
- **SC-007**: The master playlist's ID is exactly `master`, and every video rendition's ID matches the
  `<height>p_<codecs>` form (e.g. `1080p_avc1`).
- **SC-008**: 100% of JSON files written to disk are multi-line/indented and parse to the same logical
  content as a compact equivalent; the `--json` status stream remains exactly one object per line.
- **SC-009**: The structured report validates against feature 001's schema with no added, removed, or
  renamed properties; validation rules and exit codes show zero regressions versus feature 001.
- **SC-010**: With no flags the tool processes all renditions and shows no prompt; `--preselect
  <pattern>` applies the subset with no prompt; `--select` shows the pre-selected checklist on a
  terminal; passing `--all` is rejected as an unknown option.

## Assumptions

- **"Playlist ID" means the human-readable alias.** Per the user's clarification, "playlist ID" and
  "alias" refer to the same thing: the short, human-readable label shown in output and the report body
  in place of full URLs. This feature reworks feature 002's alias scheme (e.g., `video-1080p`) into the
  more differentiating scheme `master` / `<height>p_<codecs>` (e.g. `1080p_avc1`) / role-based forms for
  audio/subtitle/I-frame. The label remains a presentation device for terminal output and the
  human-readable report; it does **not** appear in, and does not change, the structured (JSON) report.
- **ID scheme details (confirmed precisely in planning).** Master → `master`; video →
  `<height>p_<codecs>` (pixel height + `p`, no `variant_` prefix), where `<codecs>` is every codec in the `CODECS` attribute trimmed to
  its sample-entry/fourCC and joined by `-` (e.g., `1080p_avc1-mp4a`; a video-only
  rendition is `1080p_avc1`); audio → slugified `LANGUAGE` (e.g. `audio_en`), appending the
  slugified `NAME` on a same-language collision (e.g. `audio_en_commentary`) and using `NAME` alone when
  `LANGUAGE` is absent; subtitles → `subs_<lang>` by the same rule; I-frame → `iframe_<height>p`;
  deterministic numeric suffix on residual collision; documented
  role-plus-ordinal fallback when attributes are absent; per-codec trimming to the fourCC keeps
  over-long codec strings readable while resolution plus codecs keep IDs unique.
- **Evidence = files from the existing artifact archive.** "Evidence" is the response file(s) the tool
  already archives for each fetch (feature 001). A continuity finding references the two consecutive
  refresh snapshots whose comparison produced it. Evidence is shown explicitly in terminal output and
  the human-readable report and is recoverable from the structured report via its existing fields (the
  artifact index plus each finding's resource and refresh information), so the frozen JSON schema does
  not change. Whether to additionally surface evidence as a new first-class structured field is **out
  of scope** here (it would break the freeze); if later desired it is a separate, versioned change.
- **The structured (JSON) report stays frozen.** Only its on-disk *formatting* changes
  (pretty-printing / indentation); its schema, fields, and values are unchanged from features 001/002.
- **"Pretty-format all generated JSONs" means files, not the status stream.** Pretty-printing applies
  to JSON files written to disk (the structured report and artifact metadata sidecars). The
  line-delimited `--json` status stream on stdout stays one compact object per line, because
  pretty-printing it would break line-delimited consumers.
- **The selection change is intentionally backward-incompatible.** `--all` is removed (processing all
  renditions is now the default, even on a TTY); the former `--select <pattern>` behavior moves to
  `--preselect <pattern>`; and `--select` is repurposed to request the interactive checklist. This is
  documented as a breaking change with migration notes; the release is versioned **0.3.0** — a minor
  bump from 0.2.0, since under SemVer the pre-1.0 (0.y.z) series carries no stable-API promise, which
  satisfies the constitution's versioning intent (consumers are warned by the 0.x line) without
  declaring 1.0 stability. (A literal Constitution V reading — breaking → MAJOR — would instead require
  a constitution amendment; that path is not taken here.)
- **The flaky live-status count is a defect to fix.** The spec states the observable contract
  (monotonic, accurate, input-resilient heartbeat); the root cause of the back-and-forth refresh count
  after Enter presses is investigated during planning/implementation.
- **Platform and automation posture are unchanged** from features 001/002: a macOS command-line tool,
  English-only, fully usable unattended/non-interactively and scriptable; all interactive-only
  behaviors degrade gracefully to non-interactive equivalents (no color/cursor control when not a TTY
  or when `NO_COLOR`/`--no-color` is set).
- **Out of scope**: any change to validation rules or the set of detected findings; new structured
  report fields; segment download / bandwidth audit (still deferred); non-HLS protocols; a graphical
  interface; localization.

## Dependencies

- **Feature 001 (HLS Stream Validator)** — its validation rules, structured report schema, and
  exit-code contract are fixed inputs that MUST NOT regress. Its artifact archive (the per-fetch files
  on disk) is the source of the evidence surfaced by US1.
- **Feature 002 (Performance and UX)** — this feature builds directly on its async session engine,
  colored/spaced output, live in-place status, Promptberry-based interactive prompt, output-directory
  handling, and live-updating reports. It reworks feature 002's alias scheme and legend into the new
  ID scheme (US3) and the start-of-session roster (US2), and tightens feature 002's live status into a
  monotonic, input-resilient heartbeat (US2).

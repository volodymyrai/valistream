# Feature Specification: Performance and UX

**Feature Branch**: `main` (no dedicated feature branch — git extension not installed)

**Created**: 2026-06-13

**Status**: Draft

**Input**: User description: "Lets move on to feature 002 -- Performance and UX. Main goal -- improve
usability drastically. In this feature I need to: make sure that all heavy operations are executed
async; make the tool to nicely report the progress and what it's currently doing; make shell
interaction nicer (use Promptberry); make shell output colored (use Rainbow); add empty line(s)
between output messages (to ease readability); allow gracefully stopping Live monitoring; allow
specifying output directory (where artefacts are stored); print output directory path on session
start; keep final report up-to-date during Live monitoring; keep final report prettified; assign
aliases to all playlist URLs in final report and use them in the main report body (to avoid URL
clutter); minor: rename executable to 'valistream' (lowercased). Basically I want this tool to be a
world standard of 'good-cli-tools'. Other improvement suggestions are welcomed." (Also: US4 —
segment bandwidth validation — is dropped from feature 001 and deferred to a separate future
feature.)

## Clarifications

### Session 2026-06-13

- Q: How should playlist aliases be formatted in the report body and legend? → A: Role + attributes
  (e.g., `video-1080p`, `audio-en`, `subs-en`, `iframe-720p`); fall back to indexed `V1`/`A1`/`S1`/`I1`
  when distinguishing attributes are unavailable; deterministic and collision-suffixed.
- Q: During live monitoring, which report file(s) must be kept continuously up to date? → A: Both the
  human-readable and the structured (machine-readable) reports update live and atomically; the
  structured report's schema stays unchanged from feature 001.
- Q: How often should the on-disk reports be rewritten during live monitoring? → A: Once per refresh
  cycle, coalescing all playlists refreshed in that cycle into a single atomic write of both reports
  (staleness ≤ one cycle).
- Q: When --output is not specified, where should each session's folder be created by default? → A:
  Under the user data directory — `~/.valistream/sessions/<session-id>/` (platform data dir on
  non-macOS); the absolute path is printed at session start.
- Q: Is user-adjustable output verbosity in scope, and at what level? → A: Yes — three flag-selected
  levels: quiet (`--quiet`: findings + errors only), normal (default), and verbose (`--verbose`: adds
  per-request/diagnostic detail). Verbosity never affects the report files or exit codes.
- Q: Does graceful stop apply only to live monitoring, or to any in-progress session? → A: Any session
  — a graceful interrupt cleanly finalizes both live monitoring and an in-progress one-shot/VOD
  validation, emitting a report (clearly marked partial) covering whatever was validated so far.
- Q: On graceful stop, how are in-flight network requests handled if they don't settle quickly? → A:
  Cancel all in-flight requests immediately on stop and finalize with what already completed; cancelled
  requests are recorded as aborted/incomplete. Guarantees a prompt, bounded shutdown with no hang.

## User Scenarios & Testing *(mandatory)*

This feature does not add new validation capabilities; it makes the existing HLS Stream Validator
(feature 001) dramatically more usable. Stories are sliced so each is an independently shippable
improvement to the user's experience, ordered by how much usability each unlocks.

### User Story 1 - Follow the Session in Real Time (Priority: P1)

An engineer starts a validation session and watches the terminal. Instead of an unresponsive pause
followed by a wall of monochrome text, they see the tool stay responsive and continuously narrate
what it is doing — "fetching master", "validating 7 of 12 media playlists", "monitoring live, 3
refreshes done" — with a live progress indicator. Messages are color-coded by severity (errors
stand out red, warnings amber, successes green) and separated by blank lines, so the output reads
like a clear running log rather than dense noise. Nothing the tool does in the background ever
freezes the display or delays the user's ability to interrupt.

**Why this priority**: Being able to see, at a glance and at all times, what the tool is doing and
how far along it is — without the screen locking up — is the single largest usability gain and the
foundation every other improvement builds on. It is independently shippable and immediately
valuable on its own.

**Independent Test**: Run a session against a multi-playlist VOD stream and a live stream; confirm
the activity description and progress counters update continuously (sub-second) throughout, that
output is color-coded by severity and visually spaced, and that the display never freezes during
large fetch/validation bursts.

**Acceptance Scenarios**:

1. **Given** a one-shot validation of a stream with many media playlists, **When** the session runs,
   **Then** the tool continuously shows the current activity and an overall progress indication
   (e.g., N of M playlists processed) that advances in near-real-time, never appearing frozen.
2. **Given** a long-running live monitoring session, **When** background fetching, validation, and
   archiving are underway, **Then** the status display keeps updating and the tool remains
   responsive to user input/interrupts throughout.
3. **Given** any output message, **When** it is rendered to an interactive terminal, **Then** it is
   color-coded by kind (error / warning / info / success) and separated from adjacent messages by
   blank line(s) for readability.
4. **Given** output is redirected to a file or pipe (non-interactive), **When** the session runs,
   **Then** no color codes, cursor movement, or animation characters appear, progress is emitted as
   plain log-friendly lines, and the captured text is fully legible.
5. **Given** the `NO_COLOR` convention is set or the user requested no color, **When** the session
   runs on a terminal, **Then** styling is disabled while all information remains present in plain
   text.

---

### User Story 2 - Stop a Live Session Without Losing Work (Priority: P2)

An operations engineer has been monitoring a live stream and has seen enough. They press the
interrupt key. Instead of the process dying and discarding the session, the tool announces it is
stopping, cancels any in-flight requests, flushes the artifact archive, finalizes a complete report
covering the whole monitored period, and confirms where everything was saved. If they are impatient
and interrupt a second time, the tool exits immediately. The same clean finalization happens whether
the session ends by completion, by graceful stop, or by an optional time limit.

**Why this priority**: Live monitoring runs for minutes to hours; losing the accumulated report and
evidence on exit would undermine the tool's core purpose. A trustworthy, graceful stop is essential
to using live monitoring at all. Depends on the responsive session loop from US1.

**Independent Test**: Start a live session, let several refreshes occur, issue a graceful stop, and
verify the tool shuts down cleanly with a complete report and flushed archive on disk; then verify a
second interrupt during shutdown forces an immediate exit.

**Acceptance Scenarios**:

1. **Given** an active live monitoring session, **When** the user issues a graceful stop, **Then**
   monitoring ends cleanly, any in-flight requests are cancelled immediately, the archive is flushed, and a
   complete end-of-session report covering the full monitored period is produced.
2. **Given** a graceful stop is in progress, **When** the user issues a second stop request, **Then**
   the tool terminates immediately, having warned that a second interrupt forces exit.
3. **Given** a live session with an optional time limit set, **When** the limit elapses, **Then** the
   session finalizes through the same clean path as a graceful stop.
4. **Given** any session-ending path (completion, graceful stop, or time limit), **When** the session
   ends, **Then** the tool reports the outcome and confirms the location of the finalized report and
   artifacts.
5. **Given** an in-progress one-shot (VOD) validation, **When** the user issues a graceful stop before
   it completes, **Then** the session finalizes cleanly with a report clearly marked partial, covering
   the playlists validated up to that point.

---

### User Story 3 - Control Where Artifacts and Reports Are Written (Priority: P3)

A user running the tool as part of a workflow wants the session's artifacts and report in a specific
place — a ticket folder, a shared drive, a scratch directory — rather than wherever the tool happens
to default. They pass an output-directory option. At session start, before anything is fetched, the
tool prints the absolute path of the folder it will write to, so they know exactly where to look.
Each session gets its own uniquely named subfolder, so running the tool twice never overwrites a
previous session's evidence.

**Why this priority**: Predictable, user-controlled artifact placement makes the tool fit into real
workflows and makes its output discoverable. Valuable but not blocking the on-screen experience, so
it follows US1–US2.

**Independent Test**: Run a session with an explicit output directory and without one; verify the
absolute session path is printed at startup in both cases, artifacts land under the chosen base
directory in a unique per-session subfolder, and a second run does not overwrite the first.

**Acceptance Scenarios**:

1. **Given** an output-directory option, **When** a session starts, **Then** the per-session folder
   is created under that directory and all artifacts and reports are written there.
2. **Given** no output-directory option, **When** a session starts, **Then** the tool uses a
   documented default location and still creates a uniquely named per-session subfolder.
3. **Given** any session, **When** it starts, **Then** the absolute path of its output folder is
   printed before fetching begins.
4. **Given** two sessions run against the same output directory, **When** both complete, **Then**
   each has its own subfolder and neither overwrites the other's artifacts.
5. **Given** an output directory that cannot be created or written to, **When** the session is
   starting, **Then** the tool fails fast with a clear, actionable error instead of failing midway.

---

### User Story 4 - A Report That's Always Current and Easy to Read (Priority: P4)

A troubleshooter wants to share or skim the findings report while a live session is still running,
and wants it to read cleanly. The human-readable report on disk is kept continuously up to date as
findings accrue and playlists refresh — not written only at the very end — and opening it at any
moment yields a complete, well-formatted document. The report is prettified: clear sections, grouped
findings, aligned summaries. Crucially, the many long playlist URLs are replaced throughout the
report body by short, meaningful aliases (e.g., `video-1080p`, `audio-en`), with a single legend
mapping every alias back to its full URL — so the report is readable instead of drowning in URLs.

**Why this priority**: A continuously fresh, clean, clutter-free report turns the tool's output into
something genuinely shareable and skimmable. It enhances already-delivered value (the report exists
from feature 001) rather than enabling a new capability, so it follows the core experience stories.

**Independent Test**: During a live session, open the on-disk report at several points and confirm it
is current (reflects recent refreshes/findings) and always a complete, valid document; inspect the
final report and confirm prettified formatting, that the body uses aliases (no raw URLs in
findings/summary sections), and that every alias resolves via the legend.

**Acceptance Scenarios**:

1. **Given** a live monitoring session, **When** the report file is opened at any point, **Then** it
   reflects the session's current state (recent findings and refreshes) and is a complete, openable
   document — never a half-written file.
2. **Given** findings accrue over time, **When** the report updates, **Then** updates are applied
   atomically so a reader never observes a partially written report.
3. **Given** the human-readable report, **When** it is read, **Then** it is prettified — sections,
   headings, findings grouped by severity and category, and aligned/tabular summaries.
4. **Given** a session that references multiple playlists, **When** the report is produced, **Then**
   every playlist is assigned a short, human-meaningful alias and the report body refers to
   playlists by alias rather than full URL.
5. **Given** any alias used in the report body, **When** the reader consults the report's legend,
   **Then** the alias maps to exactly one full playlist URL (with its role/attributes), and every
   alias is resolvable.
6. **Given** multiple refreshes of the same playlist, **When** the report updates, **Then** that
   playlist keeps the same alias throughout the session.

---

### User Story 5 - Polished Interactive Prompts (Priority: P5)

When the tool needs a decision from the user — most notably the media-playlist selection step after
the master is validated — the interaction feels modern and effortless: arrow-key navigation,
spacebar multi-select with all entries pre-selected, clear indication of what is selected, and
on-screen hints. When the tool is run unattended or the choices were supplied up front, no prompt
appears and the documented defaults are used, preserving scriptability.

**Why this priority**: A refined prompt experience is a quality-of-life polish on an interaction that
already works (feature 001's selection checklist). It is the most optional of the improvements, hence
lowest priority, and is independently shippable.

**Independent Test**: Run an interactive session and confirm the playlist-selection prompt supports
keyboard navigation and multi-select with clear affordances; run the same scenario non-interactively
(or with a pre-supplied selection) and confirm no prompt is shown and the correct default/selection
is applied.

**Acceptance Scenarios**:

1. **Given** an interactive terminal, **When** the playlist-selection step is reached, **Then** the
   user is presented a navigable multi-select prompt (pre-selected by default) with clear selection
   state and usage hints.
2. **Given** a non-interactive run or a selection supplied up front, **When** the selection step is
   reached, **Then** no prompt is displayed and the documented default/supplied selection is applied.
3. **Given** any prompt, **When** the user cancels it (e.g., interrupt), **Then** the tool exits
   cleanly with a clear message rather than leaving the terminal in a broken state.

---

### Edge Cases

- **Very small / very large terminals**: progress and the report-on-screen summary must stay readable
  on narrow terminals — long values (URLs, paths) are truncated or wrapped gracefully rather than
  breaking the layout; aliases keep the body compact.
- **Output redirected mid-pipe**: when output is piped to another program or a file, all animation,
  color, and cursor control are suppressed automatically (no garbage control sequences in logs).
- **Output directory is a relative path**: it is resolved to an absolute path, and the absolute path
  is what gets printed at startup.
- **Output directory exists and contains unrelated files**: the tool creates its own uniquely named
  per-session subfolder and never deletes or overwrites pre-existing content.
- **Output directory not writable / disk full at start**: detected at startup and reported as a
  fail-fast, actionable error before any fetching begins; disk-full *during* a session continues to
  follow feature 001's low-space warning and clean-stop behavior.
- **Graceful stop requested during startup** (before monitoring begins): the tool still exits cleanly
  and writes whatever was collected, with a report noting the early stop.
- **Second interrupt during shutdown**: forces an immediate exit; the user was warned this would
  happen.
- **Report opened by another program while being updated**: atomic updates ensure the reader sees a
  complete previous or new version, never a truncated one.
- **Two playlists that would derive the same alias** (e.g., identical role/attributes): aliases are
  de-duplicated deterministically (e.g., numeric suffixes) so every alias is unique within a session.
- **Color requested but terminal cannot render it**: the tool degrades to plain text without error.
- **Interrupt arrives while an interactive prompt is open**: the terminal is restored to a sane state
  and the tool exits cleanly.

## Requirements *(mandatory)*

### Functional Requirements

#### Cross-cutting

- **FR-001**: The tool's executable MUST be named `valistream` (all lowercase); the session start
  banner, help text, and documentation MUST refer to it by that name.
- **FR-002**: All long-running or potentially blocking operations — network fetches, playlist
  parsing, validation passes, archive writes, and report generation — MUST execute asynchronously so
  that, at all times, the tool can continue rendering status updates and respond promptly to user
  interrupts. The interface MUST NOT block on any single operation.
- **FR-003**: This feature MUST NOT change the validation rule set, the structured (machine-readable)
  report schema, or the exit-code contract established by feature 001; existing automation built on
  those MUST continue to work unchanged.
- **FR-004**: The tool MUST provide discoverable help and version output, and MUST document every
  option, including the options introduced by this feature.

#### Live progress & legible output (US1)

- **FR-005**: While work is in progress the tool MUST continuously communicate (a) what it is
  currently doing in human terms and (b) overall progress (counts/percentage where a total is known),
  updated in near-real-time.
- **FR-006**: On an interactive terminal the tool MUST render progress using live, in-place indicators
  (e.g., spinner, counters, percentage) that update without flooding the scrollback.
- **FR-007**: When output is not an interactive terminal, the tool MUST emit progress as discrete,
  plain, log-friendly lines with no color, cursor control, or animation characters.
- **FR-008**: Console output MUST use color to distinguish at least error, warning, info, and success
  message kinds and to highlight key structural elements, aiding rapid scanning.
- **FR-009**: Color and terminal styling MUST be automatically disabled when output is not an
  interactive terminal, when the `NO_COLOR` convention is present, or when the user explicitly
  requests no color; meaning MUST NOT be conveyed by color alone (severity is also labeled in text).
- **FR-010**: Distinct logical output messages MUST be separated by blank line(s) so the output is
  easy to read rather than a dense block of text.
- **FR-011**: The tool MUST provide three output verbosity levels selected by flags — quiet
  (`--quiet`: findings and errors only), normal (default: current activity, progress, and findings),
  and verbose (`--verbose`: adds per-request/diagnostic detail). Verbosity settings MUST NOT affect the
  human-readable or structured report files or the exit codes (FR-003).

#### Graceful stop (US2)

- **FR-012**: During any in-progress session — live monitoring or a one-shot validation — the user
  MUST be able to request a graceful stop (e.g., interrupt signal / documented key) that ends the
  session cleanly: any in-flight requests are cancelled immediately, the artifact archive is flushed, and a complete
  report is produced — covering the full monitored period for a live session, or whatever was validated
  so far (clearly marked partial) for a one-shot session.
- **FR-013**: A second stop request received after a graceful stop has begun MUST force immediate
  termination; the tool MUST have informed the user that a second interrupt forces exit.
- **FR-014**: All session-ending paths — normal on-demand completion, user graceful stop, and optional
  time-limit expiry — MUST converge on the same clean finalization (cancel in-flight requests, flush
  archive, finalize report, report exit status).
- **FR-015**: On stop the tool MUST clearly announce that it is shutting down and, on completion,
  confirm where the finalized report and artifacts were written.

#### Output location (US3)

- **FR-016**: The tool MUST accept a user-specified output directory (the base under which the
  per-session folder and all artifacts/reports are created) via a command-line option; when omitted it
  MUST use a documented default location — the user data directory `~/.valistream/sessions/` (the
  equivalent platform data directory on non-macOS systems), within which the per-session subfolder is
  created.
- **FR-017**: At session start, before fetching begins, the tool MUST print the absolute path of the
  session's output folder.
- **FR-018**: Each session MUST write into its own uniquely named subfolder under the chosen output
  directory; the tool MUST NOT overwrite, delete, or intermix with pre-existing content in that
  directory.
- **FR-019**: If the chosen output directory cannot be created or written to, the tool MUST fail fast
  at session start with a clear, actionable error, before any fetching begins.
- **FR-020**: A relative output path MUST be resolved to an absolute path, and the absolute path is
  what the tool reports (FR-017).

#### Live-updating, prettified, aliased report (US4)

- **FR-021**: During live monitoring the tool MUST keep both the human-readable and the structured
  (machine-readable) report files continuously up to date as findings accrue and playlists refresh, so
  the on-disk reports reflect the session's current state at any time — not only at session end. The
  structured report's schema is unchanged from feature 001 (FR-003); only its write timing changes.
  Reports are rewritten once per refresh cycle, coalescing all playlists refreshed in that cycle into a
  single atomic write (bounding staleness to one cycle).
- **FR-022**: Report file updates (both human-readable and structured) MUST be atomic: a reader
  opening either report at any moment sees a complete, valid document and never a partially written
  one.
- **FR-023**: The human-readable report MUST be prettified for readability: clear sections and
  headings, findings grouped by severity and category, and aligned/tabular summaries with consistent
  formatting.
- **FR-024**: Every playlist URL appearing in a session MUST be assigned a short, human-meaningful
  alias; the report body MUST refer to playlists by alias rather than by full URL to avoid URL
  clutter. Aliases are derived from each playlist's role and key attributes (e.g., `video-1080p`,
  `audio-en`, `subs-en`, `iframe-720p`), falling back to indexed labels (`V1`/`A1`/`S1`/`I1`) when
  distinguishing attributes are unavailable.
- **FR-025**: The report MUST include a single legend mapping every alias to its full playlist URL
  (with role/attributes); every alias used anywhere in the report MUST be resolvable through this
  legend.
- **FR-026**: Aliases MUST be stable within a session (the same playlist keeps the same alias across
  all refreshes and report updates), derived deterministically, and unique within the session
  (collisions de-duplicated deterministically).

#### Interactive prompts (US5)

- **FR-027**: Interactive prompts — notably the media-playlist selection step and any confirmations —
  MUST use a polished interactive experience: keyboard navigation, multi-select where appropriate
  (pre-selected by default for selection), clear current-selection state, and on-screen hints.
- **FR-028**: When run non-interactively (no interactive terminal) or when the relevant choices were
  supplied up front, prompts MUST be skipped and the documented defaults/inputs used, preserving
  unattended/scriptable operation.
- **FR-029**: If a prompt is cancelled or an interrupt arrives while a prompt is open, the tool MUST
  restore the terminal to a sane state and exit cleanly with a clear message.

### Key Entities *(include if feature involves data)*

- **Activity / Progress State**: The tool's current human-readable activity description plus progress
  counters (e.g., playlists processed of total, refreshes completed) surfaced live to the user.
- **Output Location**: The user-chosen (or default) base directory plus the uniquely named per-session
  subfolder where all artifacts and reports for one session are written.
- **Playlist Alias**: A short, stable, human-meaningful, session-unique label that stands in for a
  full playlist URL throughout the report; mapped to its URL and role/attributes in the report legend.
- **Session Report** *(extended from feature 001)*: Both the human-readable and structured reports,
  now continuously kept current during live monitoring. The human-readable form is prettified and
  expressed in terms of playlist aliases with a resolving legend; the structured form keeps feature
  001's schema.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: During any active session (one-shot or up to a 24-hour live session), the displayed
  activity/progress updates at least once per second while work is ongoing, and the interface never
  appears frozen.
- **SC-002**: At any moment during an active session, a user can tell what the tool is currently doing
  and how far along it is without waiting for the current operation to finish.
- **SC-003**: 100% of graceful stops (live or one-shot) produce a complete, finalized report and a
  fully flushed artifact archive; in-flight requests are cancelled immediately (not awaited) and clean
  shutdown completes within 3 seconds.
- **SC-004**: When output is redirected to a file or pipe, the captured output contains zero terminal
  color/cursor/animation control sequences and remains fully readable.
- **SC-005**: 100% of sessions print, at startup, a valid absolute output-folder path that exists and
  is where the report and artifacts are subsequently found.
- **SC-006**: At all times during live monitoring, the on-disk human-readable and structured reports
  reflect the session state no more than one refresh cycle stale, and are always complete, openable
  documents.
- **SC-007**: The report's findings and summary sections contain zero raw playlist URLs (only
  aliases), while 100% of aliases resolve to a full URL via the legend.
- **SC-008**: In usability testing, a user unfamiliar with the stream can locate a specific named
  finding in the report in under 30 seconds.
- **SC-009**: The tool is invoked as `valistream`, and its banner/help/version reflect that name.
- **SC-010**: Automation written against feature 001's structured report and exit codes runs unchanged
  against this feature (no schema or exit-code regressions).

## Assumptions

- **Named libraries are the intended implementation, confirmed at planning.** The user named
  *Promptberry* (interactive prompts) and *Rainbow* (terminal color). Requirements here are stated as
  capabilities so they remain testable and substitutable, but the intent is to adopt these libraries;
  final dependency selection (and its justification against the constitution's "prefer existing
  dependencies" rule) is recorded in the plan. New runtime dependencies are expected for this feature.
- **Default output directory**: when no output directory is specified, the tool creates each
  session's folder under the user data directory — `~/.valistream/sessions/<session-id>/` on macOS,
  the equivalent platform data directory elsewhere. The absolute path is always printed at session
  start (FR-017) so artifacts remain discoverable despite living outside the working directory.
- **Per-session subfolder naming** is deterministic and collision-resistant (e.g., timestamp plus a
  stream identifier), so concurrent or repeated runs never collide.
- **Graceful stop mechanism**: on interactive terminals the primary graceful-stop trigger is the
  interrupt key (Ctrl-C / SIGINT); a second interrupt forces immediate exit. The optional time limit
  from feature 001 finalizes through the same path.
- **Alias scheme**: aliases are derived from each playlist's role and key attributes (e.g.,
  `video-1080p`, `audio-en`, `subs-en`, `iframe-720p`), de-duplicated with numeric suffixes on
  collision, and fall back to indexed labels (`V1`, `A1`, `S1`, `I1`) when distinguishing attributes
  are unavailable. Aliases are case-stable and human-meaningful.
- **Progress cadence** target is sub-second updates while work is ongoing; **live-report freshness**
  target is within one refresh cycle.
- **This feature builds on feature 001** (HLS Stream Validator) and changes only presentation,
  performance/responsiveness, session control, and report formatting — not validation semantics, the
  structured report schema, or exit codes.
- **Platform and automation posture** match feature 001: a macOS command-line tool that must remain
  fully usable unattended (no-TTY) and scriptable; all interactive-only behaviors degrade gracefully
  to non-interactive equivalents.
- **Color/accessibility**: color is an enhancement, never the sole carrier of meaning; the palette
  is chosen to remain legible on common light and dark terminal themes.
- **Out of scope**: segment download / bandwidth verification (former feature 001 User Story 4 —
  deferred to a separate future feature); any graphical interface; changes to validation rules or the
  set of detected findings; non-HLS protocols; localization of messages (English only for this
  feature).

## Dependencies

- **Feature 001 (HLS Stream Validator)** must be present; this feature layers performance and UX
  improvements onto its session engine, archive, and report. The structured report schema and
  exit-code contract from feature 001 are treated as fixed inputs that must not regress.

# Phase 0 Research: Reliable Monitoring and Evidence

All spec clarifications were resolved before planning (12 entries, Session 2026-06-14), so there are no
open `NEEDS CLARIFICATION` items. This document records the **design decisions** that turn those
clarifications into an implementation strategy against the current 001/002 codebase, with rationale and
rejected alternatives. Each decision cites the code it touches (verified via serena on the current
tree).

---

## D1 — Evidence is a presentation-layer join over frozen data; the schema does not change

**Decision**: Surface evidence (FR-004–008) without adding any structured-report field. A finding
already carries everything needed: `Finding.resource: URL` and `Finding.refreshIndex: Int?`
(`Validation/Finding.swift`). The archive already records `IndexEntry { requestId, url, bodyPath,
metaPath }` per fetch (`Archive/SessionArchive.swift`). The evidence file for a single-snapshot finding
is recovered by **joining on the URL** (`finding.resource == IndexEntry.url`) and selecting the
snapshot at `refreshIndex`; deterministically this is the path `playlists/<id>/<id>_<refreshIndex>.m3u8`
(D6). A continuity finding cites the pair `<id>_<n-1>` and `<id>_<n>` (D4).

**Rationale**: FR-002 freezes the JSON schema **including `playlists[].id`**; FR-008 explicitly asks for
recovery "using its existing fields." A pure resolver over existing data satisfies US1 at every tier
with zero schema risk. Evidence as a new first-class structured field is called **out of scope** by the
spec (it would break the freeze).

**Critical distinction**: the structured report's frozen `playlists[].id` (a `PlaylistInfo.id` value,
unchanged) is **not** the presentation ID and **not** the archive folder name. Evidence recovery and
the artifact-index join key are the **URL**, never `playlists[].id`. The two identifiers are kept
distinct on purpose.

**Alternatives rejected**: (a) add `evidencePaths` to the JSON finding — breaks FR-002 freeze; (b) add
a line/segment locus — the spec's final clarification mandates **whole-file** evidence only.

---

## D2 — Evidence resolution is a pure core type (`EvidenceResolver`)

**Decision**: Add a pure `EvidenceResolver` (new `Session/EvidenceResolver.swift`) that maps a
`Finding` (+ the session's `AliasRegistry` and the archive's per-playlist refresh state / index) to an
`EvidenceReference` value: `.single(path)`, `.pair(olderPath, newerPath)` for continuity, or
`.unavailable(id)` when no body was captured (D5). Both `StatusRenderer` (CLI) and
`SessionReportBuilder` (report markdown) consume it so terminal and report render **identical**
references (FR-005).

**Rationale**: keeps the join logic in the pure, testable core (Constitution III), avoids duplicating
the path rule in two presenters, and guarantees terminal/report parity. Continuity vs single is decided
by `Finding.category == .continuity`.

**Alternatives rejected**: compute paths inline in each presenter — duplication + drift risk between
terminal and report; put it in the archive actor — forces an `await` into pure formatting paths.

---

## D3 — ID scheme: rework `AliasRegistry` in place (no parallel system)

**Decision**: Rewrite the private derivation in the existing `AliasRegistry`
(`Session/PlaylistAlias.swift`) to the new grammar (FR-016–020); keep the public surface
(`alias(for:role:attributes:)`, idempotent per URL, `all`, dedup) so call sites are stable.

- master → `master` (FR-017).
- video → `<height>p_<codecs>` from `RESOLUTION` height + `p`, then codecs. `<height>p_avc1`,
  `<height>p_avc1-mp4a` (FR-018). Currently `resolutionAlias` emits `video-<h>p` — drop the `video-`
  prefix and append codecs.
- `<codecs>` = **every** codec in `CODECS`, each trimmed to its sample-entry/fourCC (drop everything
  from the first `.`), joined in advertised order by `-` (`avc1.640028,mp4a.40.2` → `avc1-mp4a`). The
  `_` field separator is reserved and must never appear inside a field value.
- audio → `audio_<slug(LANGUAGE)>`; on same-language collision append `_<slug(NAME)>`
  (`audio_en_commentary`); `NAME` alone when `LANGUAGE` absent. subtitles → `subs_<…>` by the same
  rule. I-frame → `iframe_<height>p`.
- slug = lowercased, runs of non-alphanumeric collapsed to `_` (today's `normalized` lowercases and
  joins whitespace with `-` → replace).
- residual collisions → deterministic numeric suffix (existing `deduplicate`, switch separator to match
  the new grammar); attribute-less playlists → documented role+ordinal fallback (FR-020).

**Rationale**: one registry, owned by the session, is the single source of truth used by the heartbeat,
findings, report body/legend, **and** the archive folder/snapshot names (D6). Reworking in place keeps
determinism/stability/uniqueness guarantees (FR-019) already covered by `PlaylistAliasTests`.

**Alternatives rejected**: a second "ID" type beside the 002 "alias" — needless duplication; the spec
states ID and alias are the same concept. Keeping `variant_<resolution>_<codecs>` — superseded by the
clarification adopting `<height>p_<codecs>`.

---

## D4 — Snapshot identity `<id>_<n>` is a tiny pure formatter (`SnapshotID`)

**Decision**: Add `Session/SnapshotID.swift` with pure `label(id:index:) -> "\(id)_\(index)"` and a
parse helper. `<n>` is the 0-based per-playlist refresh index (first fetch `_0`). The indexed form is
used for: continuity operands (`<id>_<n-1>`/`<id>_<n>`), single-snapshot findings, every verbose trace
line, the per-refresh status line, and the archive file name (FR-018a/029). The **bare** `<id>` is used
for identity/display: roster, legend, in-place heartbeat, ID assignment.

**Rationale**: the index already exists in two places — `Finding.refreshIndex` and the archive's
`refreshCounts[playlistID]`. A single formatter prevents off-by-one drift between the file name and the
finding label, and is trivially unit-testable.

---

## D5 — Evidence-unavailable is named by ID, never by URL

**Decision**: When the producing fetch failed (no archived body), the resolver returns
`.unavailable(id)` and presenters print e.g. `WARN <id>_<n> — no body captured for <id>` (catalog row).
The `<id>` comes from the registry; if a failure prevented normal ID assignment, a deterministic
placeholder is used — `master` for the master, otherwise the role+ordinal fallback (FR-020) — so a raw
URL is **never** emitted (SC-003 holds unconditionally, FR-009). Availability is decided by whether the
archive captured a body for `(url, n)` (no matching `IndexEntry` / no file on disk).

**Rationale**: directly encodes the FR-009 clarification; preserves the zero-raw-URL invariant even on
the failure path.

---

## D6 — Archive snapshot naming: `<id>_<n>.m3u8` keyed by the real presentation ID

**Decision**: Change `SessionArchive.store(result:playlistID:)`
(`Archive/SessionArchive.swift`) so the file name is the snapshot label, not a zero-padded counter:
`playlists/<id>/<id>_<n>.m3u8` + `<id>_<n>.meta.json` (today: `%06d`). The method already takes
`playlistID`, keeps `refreshCounts[playlistID]`, and appends an `IndexEntry`; the change is the two
path strings plus passing the **real** presentation `<id>` (from the session's `AliasRegistry`) as
`playlistID`. Today the caller passes archive-ref strings (`"master"`, `"<role>-<i>"`, `"media"` in
`ValidationSession+Reporting.swift`) — switch these to registry IDs.

**Rationale**: makes every evidence file self-identifying when attached to a ticket (the user's brief),
and makes the deterministic path rule in D1/D2 hold. FR-029 explicitly permits the artifact-index path
**values** to change while the schema stays frozen.

**Risk & mitigation**: `<id>` must be filesystem-safe. The grammar yields `[a-z0-9_-]` only (slugging +
fourCC trim + `p`), so no path-separator or reserved characters arise; the dedup suffix keeps folder
names unique. A unit test asserts the safe-charset and uniqueness.

---

## D7 — Monotonic heartbeat: a session-wide refresh counter on the activity event

**Decision (root cause + fix)**: The flaky count is **architectural, not cosmetic**. Each playlist runs
its own `monitorPlaylist` loop and emits `.activity(ActivityProgress)` carrying **its own**
per-playlist `refreshes`; the single in-place heartbeat (`ProgressView.render`) shows whichever playlist
emitted last, so the number bounces between playlists at different indices. Fix: maintain **one
session-wide monotonic refresh counter** under the `ValidationSession` actor, incremented once per
completed refresh across all playlists, and carry it in the activity event (extend `ActivityProgress`
with a monotonic total field; keep per-playlist `refreshes` for context). The heartbeat shows
`<current-id> · refresh <session-total> · <elapsed>` — the displayed number only ever rises (FR-013,
SC-004). Per-playlist `<id>_<n>` indices are still used for snapshot labels/evidence.

**Rationale**: SC-004 requires the displayed count to be "monotonic non-decreasing and **equal to the
actual number of refreshes performed**" — i.e. a session total, not a per-playlist index. Centralizing
the counter in the actor makes it data-race-free and the single source of truth.

**Alternatives rejected**: display per-playlist index (inherently non-monotonic across playlist
switches); have the CLI track a max of seen indices (fragile, still wrong when playlists interleave and
restart counts).

---

## D8 — Stray-keystroke resilience: suppress terminal echo during live TTY monitoring (`LiveInputGuard`)

**Decision (root cause + fix)**: Stray input (Enter, arrows) corrupts the heartbeat because the terminal
is in cooked/echo mode, so keystrokes echo a newline that scrolls the in-place `\r…\u{1B}[K` region.
The SIGINT/SIGTERM handling is via `DispatchSource` on signals, not stdin, so nothing drains the TTY.
Fix: a CLI-only `LiveInputGuard` that, when stdout/stdin is a TTY and live monitoring is active, clears
`ECHO` (and `ICANON`) via `termios` on entry and **restores** the original `termios` on exit/cancel
(`defer`). This reuses the termios pattern already present in `PlaylistChecklist`.

**Rationale**: FR-014 + SC-004 require the status region to survive stray input. Echo suppression is the
minimal, well-understood fix; it is gated on TTY so non-interactive/piped runs are unaffected (and emit
no control bytes, per the inherited styling gate). Restoration on every exit path (normal, time-limit,
graceful stop, force-quit) is mandatory — the guard wraps the render task's lifetime.

**Alternatives rejected**: raw-mode for the whole session (over-broad; risks leaving the terminal
broken on crash); a stdin reader thread that swallows bytes (more moving parts than disabling echo).

---

## D9 — Verbose tier: additive `SessionEvent` trace cases + a pure `TraceFormatter`

**Decision**: The current `SessionEvent` (`Session/SessionConfig.swift`) has `stateChanged`,
`streamClassified`, `finding`, `monitorStateChanged`, `activity`, `sessionFolderResolved` — not enough
to trace "every action." Add **additive** cases (no schema/exit impact): `.rosterReady([RosterEntry])`
(normal-tier roster, FR-011), `.refreshCompleted(playlistID:index:errors:warnings:)` (normal-tier
per-refresh status line), and `.trace(TraceEvent)` for verbose-only actions — fetch intent, fetch
result (HTTP status/ms/bytes), per-playlist + per-rule validation outcomes incl. `OK`, archive write
(stored file), refresh scheduling/cadence (drift), continuity comparison, rendition lifecycle. A pure
`Output/TraceFormatter.swift` renders each `TraceEvent` to the catalog's category-prefixed, **ID-based**
line; the CLI gates emission by `Verbosity` per the **Output message catalog** (FR-015a/b).

**Rationale**: additive enum cases keep the core pure and don't touch the frozen JSON/exit contract
(FR-001). Formatting in core (like `ProgressFormatter`) keeps the CLI thin and the wording unit-tested.
Tier supersets (quiet ⊆ normal ⊆ verbose) are enforced in one place (the CLI render switch).

**Alternatives rejected**: a single freeform `.log(String)` — loses the category structure SC-005
checks; emitting traces only from the CLI — the CLI lacks fetch timing/per-rule data that only the core
holds.

---

## D10 — Pretty JSON for files via a *separate* encoder; the `--json` stream stays compact

**Decision**: Add `Finding.prettyJSONEncoder` (= current config `[.sortedKeys, .withoutEscapingSlashes]`
+ `.prettyPrinted`, ISO-8601 dates). Use it for the **files**: the structured report (`buildJSON`) and
the metadata sidecars (`SessionArchive.store`). **Keep** the existing compact `Finding.jsonEncoder` for
the line-delimited `--json` status stream — verified in `StatusRenderer.renderFinding`, whose `json`
branch encodes one finding per line with `Finding.jsonEncoder`. Do **not** flip the shared encoder.

**Rationale**: `.sortedKeys` already gives stable key ordering, so pretty output is deterministic and
still schema-valid (whitespace only; FR-027). Splitting the encoder is the safest way to satisfy
FR-026 (files pretty) and FR-028 (stream compact) simultaneously without coupling the two paths.

**Alternatives rejected**: flip `Finding.jsonEncoder` to pretty and give the stream its own compact
encoder — same number of constants but risks every existing compact user (incl. the NDJSON stream)
silently becoming multi-line; the chosen split keeps the stream's encoder identical to today.

---

## D11 — Selection rework: default-all, remove `--all`, split `--select`/`--preselect`

**Decision** (`ValistreamCommand.swift` + `SelectionPromptPolicy`):
- Remove the `--all` `@Flag`; passing `--all` then naturally errors as unknown (exit 2, FR-022).
- Add `--preselect <pattern>` `@Option` carrying the former `--select` pattern role (FR-023); it feeds
  `SessionConfig.selectionPatterns` and never prompts.
- Repurpose `--select` to a `@Flag` that requests the interactive checklist (FR-024); on a non-TTY it
  falls back to all + prints the documented notice (FR-025), rather than failing.
- `--select` + `--preselect` together → usage error, exit 2 (FR-025).
- Default (no flags) processes all with no prompt, **even on a TTY** (FR-021). The current
  `SelectionPromptPolicy.from(...)` keys prompting off `selectionPatterns`/nonInteractive/`all`; rewire
  it to key off the new `--select` flag (+ mutual exclusion) so the prompt appears **only** for
  `--select` on a TTY.

**Rationale**: matches FR-021–025 exactly and keeps the prompt/skip decision in the existing pure
`SelectionPromptPolicy` (already unit-tested), with the CLI just mapping the new flags.

**Alternatives rejected**: keep `--all` as a hidden no-op — the spec requires it be **rejected** as
unknown (acceptance scenario US4-2, SC-010).

---

## D12 — Version 0.3.0 with migration notes (pre-1.0 breaking change)

**Decision**: Set `MARKETING_VERSION = 0.3.0` (from 0.2.0). `--version` and help document every option
and call the selection changes out as **breaking** with migration guidance: `--all` is gone (all is the
default); `--select <pattern>` moved to `--preselect <pattern>`; `--select` is now the interactive
checklist (FR-003).

**Rationale**: recorded spec clarification — under SemVer the pre-1.0 (`0.y.z`) series carries no
stable-API promise, so a minor bump satisfies Constitution V's intent (consumers warned + migration
documented) without a false 1.0 stability claim. Tracked as the lone Constitution-Check deviation (plan
Complexity Tracking).

**Alternatives rejected**: `1.0.0` (literal MAJOR) — asserts stability not yet intended and needs a
separate constitution amendment.

---

## Cross-cutting constants (verified against the current tree)

- **Frozen** (must not change): JSON report schema + values incl. `playlists[].id`; rule set / rule IDs
  / finding catalog; exit codes 0/1/2/3 + 130. (`ReportJSONSchemaTests`, `RuleEngineTests`, conformance
  corpus guard these.)
- **Permitted structured-report changes**: pretty-print whitespace (D10); artifact-index `bodyPath`/
  `metaPath` **values** reflecting the new snapshot names (D6, FR-029).
- **Zero new dependencies**: Rainbow + Promptberry + ArgumentParser unchanged; termios is POSIX
  (already used). Core stays Foundation-only.
- **Invariant to preserve everywhere**: no raw playlist URL outside the roster (terminal) and legend
  (report), at every verbosity tier (SC-003) — the current `renderFinding` prints
  `finding.resource.absoluteString`, which **must** be replaced by the ID + evidence form.

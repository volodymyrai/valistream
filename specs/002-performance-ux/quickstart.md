# Quickstart & Validation: Performance and UX

**Feature**: 002-performance-ux | **Plan**: [plan.md](plan.md)

Runnable scenarios that prove each user story end-to-end. Implementation details live in `tasks.md`
and the code; this is a validation/run guide. Contracts referenced:
[cli-interface](contracts/cli-interface.md) · [report-format](contracts/report-format.md) ·
[terminal-output](contracts/terminal-output.md).

## Prerequisites

- macOS 14+, Xcode toolchain (Swift 6.x).
- Build via the **xcode-tools** MCP (`BuildProject` over `Valistream.xcworkspace`); analyze logs with
  `xcsift`. Unit/conformance tests: `swift test` inside `Valistream/ValistreamCore/`. Integration
  tests: Xcode scheme `Valistream` / `Valistream.xctestplan` (xcode-tools `RunSomeTests`/`RunAllTests`).
- Built binary (after rename, D9): `…/DerivedData/Valistream-*/Build/Products/Debug/valistream`.
- A reachable master playlist URL (VOD with several media playlists; and a live URL for US1/US2/US4).

## Build & name check (FR-001, SC-009)

```sh
# Build the workspace, then confirm the lowercase executable name and banner.
valistream --version      # prints valistream <semver>
valistream --help         # usage refers to the tool as 'valistream'
```

Expected: product/binary is `valistream`; help/version/banner all say `valistream`.

---

## US1 — Follow the session in real time (P1)

```sh
# Interactive TTY: continuous activity + progress, colored, blank-line separated.
valistream <vod-master-url>
```

Expected:
- A live status line updates ≥ 1×/s ("fetching master" → "validating N of M media playlists"); never
  appears frozen (SC-001, SC-002).
- Messages colored by severity AND text-labeled (`ERROR`/`WARN`/`INFO`/`OK`); logical messages
  separated by blank lines (FR-008–010).

```sh
# Non-TTY: redirect to a file — must be clean, plain, legible (SC-004).
valistream <vod-master-url> > run.log 2>&1
```

Expected: `run.log` contains **zero** color/cursor/animation control bytes; progress as plain lines.
Quick check: `LC_ALL=C grep -c $'\x1b' run.log` → `0`.

```sh
# NO_COLOR convention and explicit opt-out disable styling on a TTY (FR-009).
NO_COLOR=1 valistream <vod-master-url>
valistream --no-color <vod-master-url>
```

Verbosity (FR-011):

```sh
valistream --quiet  <vod-master-url>   # findings + errors only
valistream --verbose <vod-master-url>  # adds per-request/diagnostic detail
valistream --quiet --verbose <url>     # ERROR: mutually exclusive → exit 2
```

---

## US2 — Stop a live session without losing work (P2)

```sh
valistream <live-master-url>
# let several refreshes occur, then press Ctrl-C once.
```

Expected (FR-012–015, SC-003):
- Tool announces it is shutting down and warns a second Ctrl-C forces exit.
- In-flight requests cancelled immediately; archive flushed; a **complete** report for the monitored
  period written; final report + artifact paths confirmed; shutdown ≤ 3 s.

```sh
# Second interrupt during shutdown forces immediate exit.
valistream <live-master-url>   # Ctrl-C, then Ctrl-C again → exit 130 immediately.

# One-shot graceful stop → PARTIAL report.
valistream <vod-master-url>    # Ctrl-C before completion → report marked PARTIAL, exit reported.

# Time limit converges on the same clean path.
valistream --limit 30s <live-master-url>   # at 30s, finalizes like a graceful stop.
```

---

## US3 — Control where artifacts/reports are written (P3)

```sh
# Explicit output dir (relative is resolved to absolute and printed first).
valistream --output ./ticket-1234 <vod-master-url>

# Default location when omitted.
valistream <vod-master-url>    # base ~/.valistream/sessions/<session-id>/
```

Expected (FR-016–020, SC-005):
- Before any fetch, the **absolute** per-session folder path is printed; that folder exists and holds
  the report + artifacts.
- Two runs against the same base produce two distinct subfolders; neither overwrites the other.

```sh
# Fail-fast on unwritable output (FR-019).
valistream --output /nonexistent/root/xyz <url>   # clear actionable error, exit 2, before fetching.
```

---

## US4 — Always-current, easy-to-read report (P4)

```sh
valistream <live-master-url>
# while it runs, in another shell, open the human-readable report repeatedly.
```

Expected (FR-021–026, SC-006, SC-007):
- The on-disk human + structured reports reflect recent refreshes (staleness ≤ one cycle) and are
  always complete, openable documents (never half-written).
- Human report is prettified: sections, severity/category grouping, aligned summaries.
- Report **body** uses aliases only (`video-1080p`, `audio-en`, …) — no raw URLs; a single **Legend**
  resolves every alias to its full URL. Each playlist keeps the same alias across refreshes.

Checks:
- `LC_ALL=C grep -E 'https?://' <report.md>` shows URLs only inside the Legend section (SC-007).
- The structured JSON validates against feature 001's frozen schema (SC-010):
  [`session-report.schema.json`](../001-hls-stream-validator/contracts/session-report.schema.json).
- **Manual usability (SC-008)**: hand the report to someone unfamiliar with the stream and confirm they
  locate a specific named finding in **under 30 seconds** (validates the prettified sections + legend).

---

## US5 — Polished interactive prompts (P5)

```sh
# Interactive multi-select (arrow keys, space toggles, all pre-selected, hints).
valistream <vod-master-url>            # at the selection step, navigate + toggle.

# Skipped when non-interactive or selection supplied (FR-028).
valistream --all <vod-master-url>      # no prompt; all selected.
echo | valistream <vod-master-url>     # no TTY → no prompt; default (all).
```

Expected (FR-027–029): on a TTY the multi-select prompt appears with clear affordances; cancelling
(Ctrl-C) restores the terminal to a sane state and exits cleanly with a message.

---

## Regression gate (must stay green)

- Feature 001 unit/conformance + integration suites pass unchanged.
- Structured-report schema and exit codes unchanged (SC-010): existing automation runs as-is.
- No raw URLs in the human report body (SC-007); reports always complete on concurrent read (SC-006).

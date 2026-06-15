# Contract: Markdown Report Format (004)

**Scope**: the human-readable Markdown session report. The structured JSON report, metadata sidecars,
findings log, and `--json` stream are **frozen** ([compatibility.md](./compatibility.md)).

## 1. Structure & navigation (FR-025/026/027)

- R1. Starts with an **outcome-focused** summary (overall result before detail).
- R2. Stable, linked section order: **Summary → Incident Timeline → Findings → Playlist Information →
  Legend → Session Details**, with in-document anchor links making findings, evidence, the playlist
  legend, and session details directly navigable.
- R3. Findings are ordered **errors → warnings → informational**, preserving every finding and its
  existing evidence reference.
- R4. Uses headings, whitespace, tables, emphasis, and code spans consistently; contains **no** terminal
  styling or cursor-control bytes.

## 2. Timestamps (FR-025a/b/e, SC-003a/b/c)

- R5. Entries for findings, playlist refreshes, lifecycle events, failures, and session boundaries include
  timestamps.
- R6. Format is full ISO 8601, **local** timezone, with date, 24-hour time, milliseconds, and numeric UTC
  offset (e.g. `2026-06-15T14:03:07.412+02:00`).
- R7. An event shared with the terminal derives from the same recorded occurrence instant.

## 3. Incident timeline (FR-025c–h, SC-008a/b/c)

- R8. Exactly one chronological incident timeline listing every warning, error, operational failure,
  evidence-capture failure, shutdown/interruption, and playlist unavailable/recovered/added/removed/
  identity-changed event.
- R9. Routine successful refreshes are **excluded**; aggregate/per-playlist summaries may describe
  successful activity outside the timeline.
- R10. Ordered by occurrence timestamp; entries with equal timestamps preserve recorded sequence.
- R11. Each finding timeline entry is **compact** and **links** to exactly one complete severity-grouped
  finding entry; no finding message or evidence is duplicated in the timeline.
- R12. Repeated generation from the same recorded events yields identical timeline order.

## 4. Playlist information (FR-025h, FR-017c)

- R13. Includes the one-time information block for **every** loaded playlist, with the same fields/values as
  the normal/verbose terminal block (master = FR-017e, media = FR-017f/g, protection = FR-017b,
  missing-value rules = FR-017h).

## 5. Enrichment with graceful degradation (FR-027a)

- R14. May use GitHub alert/callout blocks (`> [!WARNING]`, `> [!CAUTION]`) and emoji severity icons so
  severity is scannable on rendering viewers.
- R15. Every styled element degrades to readable plain text: callouts → blockquotes, icons → placed beside
  their text labels.
- R16. The report MUST NOT use shields-style badges or nonstandard HTML. (Badges are README-only, FR-029a.)

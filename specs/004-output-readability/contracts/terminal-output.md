# Contract: Terminal Output (004)

**Scope**: human-readable stdout in quiet / normal / verbose modes. Machine output (`--json`) is governed by
[compatibility.md](./compatibility.md) and is **out of scope** for every styling/grouping rule below.

All rules are testable. Cross-references are to `spec.md` FR/SC.

## 1. Timestamps (FR-008a/b/c, SC-003a/b/c)

- T1. Every human-readable terminal message — headings, progress, results, findings, notices, errors,
  shutdown, summaries — is prefixed with a timestamp.
- T2. Format is exactly `[HH:mm:ss.SSS]`, 24-hour, **local** timezone, milliseconds.
- T3. The timestamp is the event's **occurrence** instant, never render time; delaying or reordering
  rendering does not change it.
- T4. The same event rendered in terminal and report refers to the same instant (correlate within 1 ms).

## 2. Information hierarchy & natural language (FR-003/006/007)

- T5. One shared hierarchy: session phase → playlist/snapshot context → operation result → findings →
  evidence → notices → final summary.
- T6. Indentation, alignment, labels, capitalization, punctuation, status vocabulary, and units are
  consistent across all human-readable output.
- T7. Messages lead with the useful outcome in plain language; no unexplained internal terminology.

## 3. Blank-line grammar / grouping (FR-004/005/017j — **user directive**)

- T8. Output is a sequence of **blocks** (`sessionSetup`, `roster`, `playlistInformation`, `refreshResult`,
  `lifecycleNotice`, `findingGroup`, `summary`).
- T9. **Exactly one** blank line separates adjacent blocks.
- T10. **No** blank line appears within a block, and **no** blank line is added after every message.
- T11. A refresh result, its findings, and its evidence form **one** contiguous block; another playlist's
  output never appears inside it.
- T12. Consecutive blanks collapse to one; there is no leading or trailing blank-line run.
- T13. A `playlistInformation` block is divided into coherent field groups, each separated by exactly one
  empty line; fields within a group stay adjacent.

## 4. Color & emphasis (FR-009/009a/010/011/011a/012)

- T14. Palette is restrained 8/16 ANSI only: error=red, warning=yellow, success=green, identifier/path=cyan,
  secondary metadata=dim gray, headings=**bold** (not colored). No 256-color/truecolor; legible on any
  background.
- T15. Each persistent **result** and **finding** line is tinted **whole-line** by severity (green/yellow/
  red). Structural context lines (headings, identifiers, evidence paths, secondary metadata) use
  token-scoped styling.
- T16. Color is never the only signal: severity label + status marker + wording convey state when color is
  off.
- T17. Styling is disabled for non-interactive output, `NO_COLOR`, `--no-color`, and `TERM=dumb`; disabled
  output contains **zero** styling or cursor-control bytes.

## 5. Status markers (FR-013, SC-005)

- T18. Markers are restrained monochrome Unicode text symbols colored by severity, each with a readable
  label: `✓ OK`, `⚠ WARN`, `✗ ERROR`.
- T19. Fallback to ASCII `[OK]` / `[WARN]` / `[ERR]` when Unicode is not reliable (`TERM=dumb`, non-UTF-8
  locale).
- T20. No colorful/variable-width emoji in terminal output.

## 6. Wrapping (FR-014, SC-006)

- T21. At 80- and 120-column widths no severity, playlist/snapshot identity, finding text, or evidence is
  silently truncated; long lines wrap/continue with recognizable indentation that keeps continuation lines
  associated with their block.

## 7. Verbosity tiers

### Quiet (FR-015/016, SC-004)
- T22. Contains all warnings, errors, required fallback/failure notices, shutdown state, and the final
  summary.
- T23. Omits routine discovery, progress, successful-refresh, diagnostic messages — and the playlist
  information block (FR-017a).
- T24. Related findings grouped by playlist/snapshot; each evidence reference stays with its finding.

### Normal (FR-008/017/017a/018, SC-002)
- T25. Shows session setup, playlist roster, concise progress, **one** persistent result per refresh
  (excluding heartbeat), findings with evidence, playlist lifecycle notices, the playlist information block
  (once per playlist), and the final summary.
- T26. Omits request/rule/comparison/archive-write/scheduling detail unless it produces a finding/failure.

### Verbose (FR-019/020/021, SC-007)
- T27. Retains every diagnostic category of the existing verbosity contract; each diagnostic is nested under
  a clear playlist/snapshot context with an unambiguous category label.
- T28. Diagnostics are visually subordinate to results/findings.
- T29. Verbose adds detail only; findings, evidence, reports, structured output, and exit status are
  identical to normal (verified by compatibility.md).

## 8. Playlist information block (FR-017a–j, SC-012/013)

- T30. Appears once per playlist at first load in normal + verbose; never repeated on later refreshes;
  absent in quiet.
- T31. Header is the bold playlist ID; detail is visually subordinate; plain output and report preserve the
  same labels/values/grouping without color (FR-017i).
- T32. Master block fields = FR-017e; media block fields = FR-017f; a media block shows only its own
  declared facts (FR-017g).
- T33. Each media block states its own protection (`None` / `Encrypted (AES-128)` / `DRM (<key format>)`);
  the master block summarizes session protection in the same vocabulary (FR-017b).
- T34. Missing values render `Unknown` vs `Not declared`; multiple observed values are listed or `Mixed`
  (FR-017h).

## 9. Heartbeat & failures (FR-024/022/023)

- T35. The in-place heartbeat is transient; it does not overwrite, split, duplicate, or visually compete
  with persistent result/finding blocks, and does not inject persistent blank lines.
- T36. The final summary states outcome, elapsed time, processed/refreshed playlist count, warning and
  error totals, and paths to the session folder and primary human-readable report when available.
- T37. Fatal/usage/operational failure messages state what failed, the context, and a practical corrective
  action when known, preserving the existing stdout/stderr and exit-code contract.

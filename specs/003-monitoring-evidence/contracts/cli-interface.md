# Contract: CLI Interface (delta over 001/002)

Only the **changes** this feature makes are normative here. Everything not mentioned is inherited
unchanged from 001/002. **Exit codes are FROZEN** (FR-001).

## Selection options (US4, FR-021–025)

| Option | Type | Behavior |
|--------|------|----------|
| *(none)* | — | Process **all** renditions, **no prompt**, **even on a TTY** (FR-021). This is the former `--all` behavior, now the default. |
| `--all` | — | **Removed.** Supplying it MUST fail as an unknown option → **exit 2** (FR-022, SC-010). |
| `--preselect <pattern>` | `@Option` (comma-separated patterns) | Select a subset up front, **no prompt** — the behavior formerly under `--select <pattern>` (FR-023). Feeds `SessionConfig.selectionPatterns`. Unattended/scriptable. |
| `--select` | `@Flag` | Request the interactive multi-select checklist with **all renditions pre-selected** (FR-024). On a **non-TTY**, fall back to all + print the documented notice (FR-025) — do **not** fail. |

**Mutual exclusion / errors**
- `--select` **and** `--preselect` together → usage error, **exit 2** (FR-025).
- `--quiet` + `--verbose` together → usage error, **exit 2** (inherited from 002).

**Prompt-appears-iff**: the interactive checklist is shown **only** when `--select` is given **and**
stdout/stdin is a TTY. No other path prompts. (Rewire `SelectionPromptPolicy.from(...)` to key off the
new `--select` flag + mutual exclusion, replacing the 002 pattern/`--all`-based rule.)

### Migration (breaking; documented per FR-003)

| Was (≤ 0.2.0) | Now (0.3.0) |
|---------------|-------------|
| `--all` | *(default — omit it)* |
| `--select <pattern>` | `--preselect <pattern>` |
| `--select` *(no value)* | `--select` *(now the interactive checklist)* |

## Version & help (FR-003)

- `MARKETING_VERSION = 0.3.0` (from 0.2.0); `--version` prints `valistream 0.3.0`.
- `--help` documents **every** option, including the reworked selection flags, and calls the selection
  changes out as **breaking** with the migration mapping above.

## Verbosity flags (US2)

`--quiet` / *(normal)* / `--verbose` — mutually exclusive (`--quiet`+`--verbose` → exit 2). Verbosity
affects **on-screen output only**; it MUST NOT change report files or exit codes (FR-015). See
`terminal-output.md` for the per-tier message catalog.

## Stale flags

`--segments` / `--tolerance` remain hidden inert flags (002 decision); not advertised, not documented in
help. No change.

## Exit codes (FROZEN — restated for review only)

| Code | Meaning |
|------|---------|
| 0 | completed, no ERROR findings |
| 1 | completed, ≥1 ERROR finding |
| 2 | usage / IO / invalid-URL error (stderr) |
| 3 | operational failure |
| 130 | graceful stop (SIGINT/SIGTERM) |

This feature MUST NOT add, remove, or repurpose any exit code (SC-009).

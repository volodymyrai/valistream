# Contract: Report Format (delta over 001/002)

Two reports are written per session (inherited from 001/002): the **human-readable Markdown** report
and the **structured JSON** report. This feature changes the Markdown body (evidence + ID scheme) and
the **on-disk formatting** of every JSON file. The JSON **schema/fields/values are FROZEN** (FR-002).

## Structured JSON report (FROZEN schema; formatting only)

- Schema, field names, types, and **values** (incl. `playlists[].id`) are unchanged from 001 (FR-002,
  SC-009). `ReportJSONSchemaTests` MUST continue to pass.
- **Pretty-printed** on disk: indented, multi-line, stable key ordering (FR-026). Implemented via the
  new `Finding.prettyJSONEncoder` (`[.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]`). Pretty
  output differs from compact only by whitespace, so it still validates (FR-027).
- The **artifact-index path values** (`bodyPath`/`metaPath`) reflect the new snapshot names
  `playlists/<id>/<id>_<n>.m3u8` (FR-029) — values only; the `IndexEntry` shape is unchanged.
- `playlists[].id` is the frozen internal identifier; it is **not** the presentation ID and **not** the
  archive folder name. Evidence is recoverable from `resource` (URL) + `refreshIndex` (see
  `evidence-and-ids.md`), so no schema change is needed for US1.

## Metadata sidecars (`*.meta.json`)

- Renamed to `<id>_<n>.meta.json` (FR-029).
- **Pretty-printed** via `Finding.prettyJSONEncoder` (FR-026).

## `--json` status stream (NOT a file)

- Stays **one compact JSON object per line** (FR-028) via the existing compact `Finding.jsonEncoder`.
  Pretty-printing MUST NOT be applied here — line-delimited consumers must keep working (SC-008).

## Human-readable Markdown report (US1/US2/US3)

- **Body refers to playlists by ID** (the new scheme); **no raw URLs** in the body (FR-012, SC-003).
- **Legend** section maps each ID → full URL + role/attributes (the only place URLs appear).
- **Findings**: every ERROR and WARN carries the **same** evidence reference(s) as the terminal,
  rendered as an **inline code span containing the relative archive path only** — e.g.
  `` `playlists/1080p_avc1/1080p_avc1_5.m3u8` `` — **not** a Markdown link, so it stays copy-pasteable
  and viewer-agnostic (FR-005). Continuity findings show **two** spans, `<id>_<n-1>` and `<id>_<n>`
  (FR-006). Unavailable evidence → `no body captured for <id>` (ID, never a URL; FR-009).
- Pretty/larger byte size is acceptable; logical content and schema validity unchanged (edge case).

## What MUST NOT change (SC-009)

Validation rule set, rule IDs, finding catalog, the JSON schema/fields/values, and exit codes — all
frozen. The only permitted structured-report changes are pretty-print whitespace and artifact-index
path **values**.

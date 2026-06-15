# Contract: Compatibility Freeze (004)

**Scope**: surfaces that feature 004 MUST NOT change (FR-002/FR-028, SC-011). These are verified by
automated guard tests; human-readable styling/grouping MUST be gated off for every machine surface below.

## Frozen surfaces

- C1. **Validation results** — same findings for the same inputs (rules unchanged).
- C2. **Identifiers** — rule IDs, finding IDs, playlist IDs (`playlists[].id` / `AliasRegistry` grammar),
  snapshot IDs unchanged.
- C3. **Evidence resolution** — `EvidenceResolver` join on URL + `refreshIndex` unchanged.
- C4. **Structured JSON report** — schema **v1** keys, values, ordering, and pretty formatting unchanged
  (`ReportJSONSchemaTests` is the anchor).
- C5. **Metadata sidecars** — `.meta.json` shape and pretty formatting unchanged.
- C6. **Findings log** — `FindingsLog` JSON Lines (one compact object per line, `0x0A`-terminated)
  unchanged.
- C7. **`--json` status stream** — line-delimited compact objects to stdout, no styling/blank-line grammar,
  no timestamps injected into the machine stream.
- C8. **Selection behavior** — `--select` / `--preselect` semantics and default-all behavior unchanged.
- C9. **Exit codes** — `0` success, `1` findings, `2` usage, `3` operational failure, `130` interrupt;
  unknown option → `2`.

## Gating rule

- C10. The blank-line grammar (terminal-output T8–T13), color/markers (T14–T20), and human timestamps
  (T1–T4) apply **only** to human-readable stdout. When output is non-interactive, `--json`, `NO_COLOR`,
  `--no-color`, or `TERM=dumb`, no styling or cursor-control bytes are emitted (SC-005), and the machine
  stream carries no human grouping/spacing.

## Verification

- V1. Re-run the 003 guard suite (`ReportJSONSchemaTests`, RuleEngine/conformance, exit-code checks) — zero
  regression.
- V2. Add tests asserting `--json` output for a scripted session is byte-identical in structure before/after
  004 (no timestamps, no blank-line grammar, no ANSI).
- V3. Add a normal-vs-verbose equivalence test: identical findings, evidence, report files, structured
  output, and exit status across verbosity tiers (FR-021, SC-011).

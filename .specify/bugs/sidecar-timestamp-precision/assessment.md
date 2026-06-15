# Bug Assessment: Sidecar `.meta.json` timestamps lack ms/offset + no fetch duration field

- **Slug**: sidecar-timestamp-precision
- **Created**: 2026-06-15
- **Source**: pasted text + local file `/Users/volodymyr.akimenko/Downloads/1080p_avc1-mp4a_82.meta.json`
- **Verdict**: valid (data-fidelity defect + accepted enhancement; all decisions locked — ready to fix)
- **Severity**: medium
- **Scope**: two coupled items — (A) full-precision timestamps in the sidecar; (B) add a fetch
  **duration in milliseconds** field to the sidecar (enhancement; no existing requirement — see below).

## Report (verbatim or summarized)

> I don't see full timestamp added to playlist sidecar files. See file: `/Users/volodymyr.akimenko/Downloads/1080p_avc1-mp4a_82.meta.json`

The referenced sidecar records:

```json
"requestStartedAt" : "2026-06-15T15:46:00Z",
"responseEndedAt" : "2026-06-15T15:46:00Z",
```

Both timestamps are truncated to whole seconds and use `Z`, not the full
ISO-8601-with-milliseconds-and-numeric-offset form feature 004 introduced for
the human report (`2026-06-15T14:03:07.412+02:00`).

## Symptom

- **Observed**: `requestStartedAt` / `responseEndedAt` in `.meta.json` sidecars serialize as
  `2026-06-15T15:46:00Z` — second resolution only, UTC `Z`. Request start and response end collapse to
  the same value, so fetch latency and millisecond correlation to terminal `[HH:mm:ss.SSS]` output are
  lost.
- **Expected**: full ISO-8601 with date, 24-hour time, **milliseconds**, and **numeric UTC offset**,
  matching the Markdown report's `ReportTimestampFormatter` (e.g. `2026-06-15T17:46:00.123+02:00`).
- **(B) Duration**: the sidecar exposes `requestStartedAt` + `responseEndedAt` but **no explicit
  fetch-duration field**. A reader must subtract two strings — and with the current second-resolution
  timestamps they're identical (`…15:46:00Z`), so latency is unrecoverable from the file. Add an explicit
  `durationMs` (integer milliseconds) derived from the two `Date` values.

### Was duration ever a requirement?

No. Searched `specs/004-output-readability` and `specs/003*`: every "duration" hit is **HLS segment
duration** (`targetDuration`, observed median + min–max segment durations — FR-017d / data-model.md §5),
not request/response latency. No FR, contract, or schema mandates a network-duration field. So item (B)
is a **net-new enhancement**, not a missed requirement — adding it here per your request.

## Reproduction

1. Run a validation/monitoring session that archives playlist fetches to an output dir.
2. Open any `playlists/<id>/<id>_<n>.meta.json` sidecar.
3. Inspect `requestStartedAt` / `responseEndedAt` → values are `…T..:..:..Z`, no `.SSS`, no `+HH:MM`.
4. Compare with the Markdown report's `Started` / `Ended` rows, which carry milliseconds + offset.

## Suspected Code Paths

- `Valistream/ValistreamCore/Sources/ValistreamCore/Validation/Finding.swift:144` —
  `prettyJSONEncoder` sets `dateEncodingStrategy = .iso8601`. The Foundation `.iso8601` strategy uses
  `ISO8601DateFormatter` with default options (`.withInternetDateTime` only): no fractional seconds,
  emits `Z`. **Root cause.** Same on `jsonEncoder` (`Finding.swift:139`).
- `Valistream/ValistreamCore/Sources/ValistreamCore/Archive/SessionArchive.swift:85` — sidecar is
  `Finding.prettyJSONEncoder.encode(record)`; the `ArtifactRecord` `Date` fields inherit the lossy
  strategy. The archive never routes these through `ReportTimestampFormatter`.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Networking/StreamFetching.swift:110-143` —
  `ArtifactRecord.requestStartedAt` / `responseEndedAt` are `Date` (sub-second precision is present in
  the value; only the serialization truncates it). **Item (B)**: this struct is where a new `durationMs`
  field is added; `init(requestId:bodyPath:result:)` (line 127) is where it is computed from
  `result.metadata.responseEndedAt.timeIntervalSince(requestStartedAt)`. Note: duration derives from the
  raw `Date`s, so it is accurate **regardless** of the timestamp string precision — but it is the value
  that makes item (A)'s loss visible, which is why the two are coupled.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Output/TimestampFormatter.swift:28` —
  `ReportTimestampFormatter` already produces the desired form ("Never uses `Z` — always emits
  `+HH:MM`"); only the Markdown report (`SessionReportBuilder.swift:211-212,306`) uses it.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Validation/Finding.swift:152` — `jsonDecoder` uses
  `.iso8601` (parses `.withInternetDateTime` only). **Round-trip trap**: switching the encoder to emit
  fractional seconds breaks `SessionArchiveTests.swift:116` and any decode of existing archives unless
  the decoder is updated in lockstep.

## Root Cause Hypothesis

The `.meta.json` sidecar relies on the shared `Finding.prettyJSONEncoder`, whose
`dateEncodingStrategy = .iso8601` emits second-resolution UTC (`…Z`). Feature 004's full-precision
timestamp formatter (`ReportTimestampFormatter`) was wired only into the Markdown report, not into the
JSON serialization path. So the archived evidence keeps the pre-004 (feature 003) format. **Confidence:
high** — directly traced from the sidecar value to the encoder strategy.

## Proposed Remediation

**Item (B) — duration field** (decisions locked): Add **required** `public let durationMs: Int` to
`ArtifactRecord` and compute it in `init(requestId:bodyPath:result:)` as
`Int((result.metadata.responseEndedAt.timeIntervalSince(result.metadata.requestStartedAt) * 1000).rounded())`
(clamp negatives to 0 in case of clock skew). Keep synthesized `Codable`; field is **non-optional**.
**Sidecar-only** — no `durationMs` in the JSON/Markdown report, no change to the live `ResponseMetadata`.
Existing `.meta.json` fixtures/golden tests are **regenerated** to include the field (accepted: old
archives without it will not decode against the new required field). Items (A) and (B) ship together so a
reader gets both a precise pair of instants and the pre-computed elapsed time.

**Item (A) — timestamp precision** (decisions locked: **UTC**, **dedicated encoder**, **in-scope 004**):
Add a **dedicated sidecar encoder/decoder pair** (e.g. private `static let metaEncoder` /
`metaDecoder` on `SessionArchive`, or a small `ArchiveJSON` helper) and use it in
`SessionArchive.store` instead of `Finding.prettyJSONEncoder`. Its `dateEncodingStrategy = .custom`
serializes each `Date` as full ISO-8601 with milliseconds and a **`+00:00`** offset, reusing the
existing `ReportTimestampFormatter.format(date, timeZone: .gmt)` (it never emits `Z`, always `+HH:MM`,
so UTC renders `…+00:00`). Matching `dateDecodingStrategy = .custom` parses
`ISO8601DateFormatter` with `[.withInternetDateTime, .withFractionalSeconds]`.

- **Shared `Finding.prettyJSONEncoder` / `jsonEncoder` / `jsonDecoder` stay UNTOUCHED.** The FROZEN JSON
  report schema v1 and `FindingsLog` JSONL keep their current `.iso8601` (`Z`, second-resolution) output
  — zero blast radius on frozen artifacts.
- Accepted inconsistency: the machine **JSON report** Date fields (`startedAt`/`endedAt`/`observedAt`)
  remain `…Z` second-resolution, while the **Markdown report** (via `ReportTimestampFormatter`) and now
  the **sidecar** carry milliseconds. Out of scope for this bug.
- **In-scope feature 004**: treat as part of 004 delivery — add a sidecar line to the data-model /
  contracts (sidecar timestamps = full ISO-8601 UTC + ms; new `durationMs`) during the fix so artifacts
  stay consistent with the spec. No separate amendment cycle.

Because the sidecar gets its **own** encoder, `ReportTimestampFormatter`'s offset/millisecond logic can
stay where it is — no extraction needed; the `.custom` closure just calls it with `timeZone: .gmt`.

**Files likely to change**:
- `Valistream/ValistreamCore/Sources/ValistreamCore/Networking/StreamFetching.swift` — add required
  `durationMs: Int` field + computation to `ArtifactRecord` (item B).
- `Valistream/ValistreamCore/Sources/ValistreamCore/Archive/SessionArchive.swift` — dedicated
  `metaEncoder`/`metaDecoder` with the `.custom` UTC+ms date strategy; `store` uses `metaEncoder`
  instead of `Finding.prettyJSONEncoder` (item A).
- `Valistream/ValistreamCore/Sources/ValistreamCore/Output/TimestampFormatter.swift` — **no change**
  (reused as-is with `timeZone: .gmt`).
- `Valistream/ValistreamCore/Sources/ValistreamCore/Validation/Finding.swift` — **no change** (shared
  encoders stay `.iso8601`).
- `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Archive/SessionArchiveTests.swift` — decode via
  the new `metaDecoder`; assert `durationMs` + full-form timestamps.
- `Valistream/Valistream/ValistreamIntegrationTests/PrettyJSONFilesTests.swift`
- Spec sync: `specs/004-output-readability/data-model.md` (+ relevant contract) — document sidecar
  timestamp format + `durationMs` (in-scope 004).
- Any golden/snapshot sidecar fixtures asserting the `…Z` form or lacking `durationMs` → regenerate.

**Tests to add or update**:
- Assert sidecar `requestStartedAt`/`responseEndedAt` match the UTC full-form regex
  `\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}\+00:00` (deterministic — no local-tz dependence).
- Round-trip: `metaEncoder` → `metaDecoder` on `ArtifactRecord` preserves the instant within 1 ms.
- Confirm `requestStartedAt` ≠ `responseEndedAt` when the fetch spans sub-second time (latency
  observable in the serialized form, not just the `Date`).
- **(B)** `durationMs` equals `round((responseEndedAt − requestStartedAt) × 1000)` for a known
  scripted-transport fetch; equals 0 (not negative) when start ≥ end; field present and **required** in
  the encoded sidecar JSON.

## Risks & Considerations

- **Frozen artifacts — avoided**: by using a **dedicated** sidecar encoder, the shared
  `Finding.prettyJSONEncoder`/`jsonEncoder`/`jsonDecoder` are untouched, so the FROZEN JSON report schema
  v1 and `FindingsLog` JSONL formats do not change. Zero blast radius there.
- **Decoder lockstep (sidecar only)**: `SessionArchiveTests` currently decodes via `Finding.jsonDecoder`
  (`.iso8601`, no fractional seconds) — that decode **must** switch to the new `metaDecoder`, or it
  fails on the new fractional-second sidecars.
- **Accepted format split**: machine JSON report keeps `…Z` second-resolution; Markdown report + sidecar
  carry milliseconds. Intentional (frozen-schema-preserving). Document so it is not later flagged as a
  regression.
- **(B) Required field on a FROZEN sidecar** (decided: non-optional, regenerate fixtures): `durationMs`
  is additive (new key) but **required**, so Swift decode of any **pre-existing** archive lacking the key
  fails. Accepted trade-off — all `.meta.json` fixtures/golden assertions are regenerated to carry the
  field. No back-compat decode path. Scripted-transport latency must be deterministic in the new tests
  (pin the stubbed start/end instants).

## Open Questions

All resolved — ready for `/speckit-bug-fix`.

- ~~sidecar offset: local vs UTC~~ → **RESOLVED**: **UTC** (`+00:00`, never `Z`), full ISO-8601 + ms.
- ~~shared vs dedicated encoder~~ → **RESOLVED**: **dedicated** sidecar encoder/decoder; frozen JSON
  report + FindingsLog untouched.
- ~~in-scope 004 vs spec amendment~~ → **RESOLVED**: **in-scope feature 004**; sync data-model/contract
  during the fix.
- ~~field name/type + report surfacing for (B)~~ → **RESOLVED**: `durationMs: Int`, **sidecar-only**.
- ~~optional vs required `durationMs`~~ → **RESOLVED**: **required** (non-optional); regenerate fixtures,
  no back-compat decode.

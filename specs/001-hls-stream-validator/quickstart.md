# Quickstart: HLS Stream Validator

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

Runnable scenarios proving the feature end-to-end. Interface details:
[contracts/cli-interface.md](contracts/cli-interface.md); archive/report shapes:
[data-model.md](data-model.md).

## Prerequisites

- macOS 14+, Xcode 16+ (Swift 6 toolchain)
- Network access for the public-stream scenarios

## Build & Test

The library + tests live in the SwiftPM package (`Valistream/ValistreamCore/`); the CLI is an Xcode tool
target built through the workspace (`Valistream/Valistream.xcworkspace`).

```bash
# Library + unit/conformance tests (SwiftPM package)
( cd Valistream/ValistreamCore && swift test 2>&1 | xcsift )   # unit + conformance (corpus)

# CLI tool + integration tests (Xcode workspace, scheme "Valistream")
xcodebuild -workspace Valistream/Valistream.xcworkspace -scheme Valistream build 2>&1 | xcsift
xcodebuild -workspace Valistream/Valistream.xcworkspace -scheme Valistream test 2>&1 | xcsift  # + integration (stubs)

# Run the built CLI (resolve the product path once, then reuse it)
VALISTREAM=$(find ~/Library/Developer/Xcode/DerivedData -type f -name Valistream \
  -path '*/Build/Products/*' -perm +111 | head -1)
"$VALISTREAM" --help                                    # contract sanity check
```

Expected: tests pass; build succeeds; help output matches the CLI contract. The scenarios below use
`valistream` as shorthand for the built binary (`"$VALISTREAM"`).

## Scenario 1 — One-shot VOD validation (US1)

Apple's reference stream (conformant):

```bash
valistream "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8" --all
```

Expected: stream classified `vod`; master + all media playlists fetched and validated; live status
visible during the run; summary with **0 error findings**; exit code `0`; session folder under
`./valistream-sessions/<session-id>/` containing every playlist + `.meta.json` sidecars +
`report.json` + `report.md` (SC-001, SC-002 negative half, SC-004).

## Scenario 2 — Seeded violations are caught (US1 / SC-002)

Serve a broken fixture locally (corpus file with known violations, e.g. missing
`EXT-X-TARGETDURATION`):

```bash
python3 -m http.server 8000 --directory Tests/ValistreamCoreTests/Fixtures/streams/broken-vod &
valistream "http://localhost:8000/master.m3u8" --all
```

Expected: error findings naming the violated rules with playlist + line locations; exit code `1`.

## Scenario 3 — Live monitoring with playlist selection (US2)

```bash
valistream "<live-master-url>" --limit 5m
```

Expected: stream classified `live`; interactive checklist of discovered playlists (all
pre-selected) appears; after confirming, selected playlists refresh on cadence (status shows
per-playlist state); session ends at the 5-minute limit with a summary; report records monitored
vs. excluded playlists (FR-018). Continuity faults (staleness, sequence regression) — exercised
deterministically in `ValistreamIntegrationTests` via scripted in-process live-stream scenarios.

## Scenario 4 — Unattended automation (Clarification #2)

```bash
valistream "<live-master-url>" --limit 90s --non-interactive --json --quiet \
  | tee findings.jsonl
echo "exit: $?"
```

Expected: no prompt; JSON Lines findings on stdout; exit `0`/`1` usable as CI pass/fail signal.

## Scenario 5 — Segment bandwidth audit (US4)

```bash
valistream "<vod-master-url>" --segments --tolerance 10 --all
```

Expected: every segment of every selected playlist downloaded into
`<session>/segments/<playlist-id>/`; segments whose implied bitrate exceeds declared
`BANDWIDTH`/`AVERAGE-BANDWIDTH` by > 10% flagged as `segment`-category findings; segment audit
totals in the report.

## Scenario 6 — Interruption keeps evidence (US3)

Start Scenario 3, press Ctrl-C mid-run.

Expected: graceful shutdown; exit `130`; session folder contains all artifacts collected so far,
`findings.jsonl` intact, and a final `report.json`/`report.md` marked as interrupted (US3
scenario 3, FR-015).

## Verification checklist

- [ ] Scenario 1 exits `0` with zero error findings on the Apple reference stream
- [ ] Scenario 2 exits `1` and names each seeded violation with location
- [ ] Scenario 3 shows the checklist, honors selection, stops at `--limit`
- [ ] Scenario 4 emits valid JSON Lines and a meaningful exit code with no prompt
- [ ] Scenario 5 flags only segments beyond tolerance
- [ ] Scenario 6 leaves a complete, readable session archive after Ctrl-C
- [ ] `swift test` (package) green on the conformance corpus; `Valistream` scheme test plan green on integration scenarios

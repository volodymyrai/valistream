<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:
`specs/004-output-readability/plan.md`

Active feature: 004-output-readability (Readable Output and Onboarding)
- Spec: specs/004-output-readability/spec.md
- Plan: specs/004-output-readability/plan.md
- Design: data-model.md, contracts/, research.md, quickstart.md (same directory)
- Builds on: 003-monitoring-evidence (+001/002). FROZEN: validation results, rule/finding/playlist/
  snapshot IDs, evidence resolution, JSON report schema v1, `.meta.json`, `FindingsLog` JSONL, `--json`
  stream, selection, exit codes 0/1/2/3/130. Reuses existing output layer (TerminalOutputMode/
  TerminalWriter/Rainbow/ProgressFormatter/TraceFormatter)
- Scope (presentation-only): occurrence timestamps on every human message (terminal `[HH:mm:ss.SSS]`,
  report ISO-8601+offset); blank-line grouping grammar (exactly one blank between logical groups, none
  within — disabled for `--json`); whole-line severity tint + presentation roles + Unicode/ASCII status
  markers; one persistent result per refresh; one-time playlist information block (master/media fields +
  protection None/Encrypted(AES-128)/DRM via additive EXT-X-KEY/SESSION-KEY metadata); incident timeline
  in report; playlist lifecycle events; README rewrite + coverage badge; version 0.4.0. No new dependency
- Stack: Swift 6 (strict concurrency), SwiftPM + Xcode workspace. Core `ValistreamCore` stays
  dependency-free; CLI target deps: swift-argument-parser + Rainbow (color) + Promptberry (prompts)
- Build/test: xcode-tools `BuildProject`; `swift test` (unit) — pipe through `xcsift`. Coverage enabled
  in `Valistream.xctestplan` (Valistream + ValistreamCore) → read via `xcrun xccov` for README badge

Implementation rules (binding):
- Code style: follow `styleguide.md` (repo root)
- Test code: follow `unit-testing.md` (repo root)
- Consult skills while implementing: `swift-testing-pro`, `swift-concurrency-pro`,
  `swift-api-design-guidelines`, `swift-architecture`, `swift-language`
- Integration tests use scripted in-process transport stubs — no local HTTP server
<!-- SPECKIT END -->


## Additional implementation rules (binding)

Do before impl start:
1. Activate project in **serena**
2. Check availability of **serena** and **xcode-tools** MCPs. Hard stop if any not avail. Ask user to fix

### Serena

Must use **serena** for:
- code inspection, semantic retrieval
- code editing
- memory management

**Warning:** For Bash code inspection → **explicit** permission needed!


### Xcode-tools

Must use **xcode-tools** for:
- code experiment & validate → `ExecuteSnippet`
- build validation → `BuildProject`, `XcodeListNavigatorIssues`, `GetBuildLog`, `XcodeRefreshCodeIssuesInFile`
- documentation search → `DocumentationSearch`


### Memory

Use **serena** tools for memory management!
No built-in memory usage


### Documentation lookup

1. **xcode-tools** `DocumentationSearch`

Hard stop if not avail! Ask user to fix.
**Warning:** No WebSearch is allowed!

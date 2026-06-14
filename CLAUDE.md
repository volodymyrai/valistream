<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:
`specs/003-monitoring-evidence/plan.md`

Active feature: 003-monitoring-evidence (Reliable Monitoring and Evidence)
- Spec: specs/003-monitoring-evidence/spec.md
- Plan: specs/003-monitoring-evidence/plan.md
- Design: data-model.md, contracts/, research.md, quickstart.md (same directory)
- Builds on: 001-hls-stream-validator + 002-performance-ux (validation rules, JSON report schema,
  exit codes are FROZEN — incl. `playlists[].id`; reworks 002's alias scheme into the new ID scheme)
- Scope: evidence files for every ERROR/WARN; monotonic input-resilient heartbeat; `<height>p_<codecs>`
  IDs; default-all selection (`--all` removed, `--select`/`--preselect` reworked); pretty-printed JSON
  files. No new dependency. Ships 0.3.0 (breaking CLI change, migration documented)
- Stack: Swift 6 (strict concurrency), SwiftPM + Xcode workspace. Core `ValistreamCore` stays
  dependency-free; CLI target deps: swift-argument-parser + Rainbow (color) + Promptberry (prompts)
- Build/test: xcode-tools `BuildProject`; `swift test` (unit) — pipe through `xcsift` for log analysis

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

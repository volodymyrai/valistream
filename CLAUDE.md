<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:
`specs/001-hls-stream-validator/plan.md`

Active feature: 001-hls-stream-validator (HLS Stream Validator)
- Spec: specs/001-hls-stream-validator/spec.md
- Plan: specs/001-hls-stream-validator/plan.md
- Design: data-model.md, contracts/, research.md, quickstart.md (same directory)
- Stack: Swift 6 (strict concurrency), SwiftPM; deps: swift-argument-parser only
- Build/test: `swift build` / `swift test` — pipe through `xcsift` for log analysis

Implementation rules (binding):
- Code style: follow `styleguide.md` (repo root)
- Test code: follow `unit-testing.md` (repo root)
- Consult skills while implementing: `swift-testing-pro`, `swift-concurrency-pro`,
  `swift-api-design-guidelines`, `swift-architecture`, `swift-language`
- Integration tests use scripted in-process transport stubs — no local HTTP server
<!-- SPECKIT END -->


## Additional implementation rules (binding)

**Project layout (after Xcode restructure):**
- SwiftPM package -> `Valistream/ValistreamCore/` -- builds the `ValistreamCore` library +
  `ValistreamCoreTests` (unit/conformance) only
- CLI tool -> `Valistream/Valistream/Valistream.xcodeproj` target **Valistream** (sources in
  `Valistream/Valistream/Valistream/`); depends on `ValistreamCore` + `ArgumentParser` via SwiftPM
- Integration tests -> target **ValistreamIntegrationTests** (unit-test bundle in the CLI xcodeproj),
  sources in `Valistream/Valistream/ValistreamIntegrationTests/` (stubs in `Support/`:
  `ScriptedStreamFetcher`, `ManualClock`)
- Test plans -> `Valistream/TestPlans/`: `ValistreamCore.xctestplan` (unit only; package scheme
  `ValistreamCore`) and `Valistream.xctestplan` (unit + integration; CLI scheme `Valistream`)
- Workspace -> `Valistream/Valistream.xcworkspace` ties the project and package together
- Build/run the CLI through the workspace (**xcode-tools** `BuildProject`);
  `swift test` inside `Valistream/ValistreamCore/` covers the library + unit tests only — integration
  tests run via the Xcode `Valistream` scheme / `Valistream.xctestplan`

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

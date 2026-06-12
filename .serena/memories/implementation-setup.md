# Valistream implementation setup

## Layout (after Xcode restructure — June 2026)
Workspace `Valistream/Valistream.xcworkspace` (xcode-tools tab `windowtab1`) joins two members:

- **SwiftPM package** -> `Valistream/Package/` — builds `ValistreamCore` library + test targets ONLY (no executable).
  - `Package/Sources/ValistreamCore/{Playlist,Validation,Validation/Rules,Monitoring,Networking,Archive,Segments,Session}/`
  - `Package/Tests/ValistreamCoreTests/` (+ `_setup/Tags.swift`, `Fixtures/`), `Package/Tests/ValistreamIntegrationTests/Support/`
  - swift-tools 6.3, swiftLanguageModes [.v6], platforms macOS 14. Only product: `.library(ValistreamCore)`. NO external deps now (swift-argument-parser removed from package).
- **CLI Xcode project** -> `Valistream/Valistream/Valistream.xcodeproj`, target `Valistream` (product-type tool, SWIFT_VERSION 6.0).
  - Sources are a FileSystemSynchronizedRootGroup at `Valistream/Valistream/Valistream/` (drop files in, no pbxproj edit needed): `ValistreamCommand.swift` (@main, AsyncParsableCommand), `StatusRenderer.swift`.
  - Package product deps: `ValistreamCore` (LOCAL — from workspace member `Package`, XCSwiftPackageProductDependency with NO `package` key) + `ArgumentParser` (REMOTE — XCRemoteSwiftPackageReference swift-argument-parser >=1.5.0, resolved 1.8.2; listed in project packageReferences).
  - Built binary name = `Valistream` (capital, PRODUCT_NAME=$(TARGET_NAME)). CLI/help invocation name still `valistream` (ArgumentParser commandName).

## Task->path mapping (tasks.md)
`Sources/ValistreamCore/...` -> prefix with `Valistream/Package/`. CLI `Sources/valistream/...` -> now `Valistream/Valistream/Valistream/` (Xcode target, not the package).

## Build / test (binding: xcode-tools MCP, tab windowtab1)
- Build CLI + its deps: `BuildProject` (builds workspace; resolves packages, compiles ValistreamCore + CLI). Verified green; CLI `--version`->0.1.0, bad URL->exit 2.
- Package lib/tests: `swift test` inside `Valistream/Package/` (RunAllTests via workspace only if a scheme covers the package test targets — not confirmed).
- Test subset: `RunSomeTests` [{targetName, testIdentifier}].
- Built CLI binary path: DerivedData `.../Valistream-*/Build/Products/Debug/Valistream`.

## IMPORTANT: Serena LSP unavailable for Swift
serena symbol tools + `replace_content`/`replace_symbol_body` FAIL ("No language servers available"). Use built-in Edit/Write for Swift edits. serena ALSO has no `search_for_pattern`/`find_file`/`list_dir` exposed here. serena memory tools work. For text search use Bash grep (docs only — Bash *code* inspection needs explicit permission per CLAUDE.md). For whitespace-sensitive structured edits (pbxproj, fenced md) a python script with assertions is reliable.

## Conventions (binding)
- Code: `styleguide.md` (repo root) — 4-space indent, else/catch on new line, file header block, MARK order, no Foundation when Swift-native exists.
- Tests: `unit-testing.md` — Swift Testing only, struct suites, `#require` not force-unwrap, `== false` not `!`, area tag per suite from `_setup/Tags.swift`.

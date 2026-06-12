# Valistream implementation setup

SwiftPM package root: `Valistream/` (NOT repo root). Xcode has it open.

## Targets (Package.swift)
- `ValistreamCore` library — all domain logic, dir `Valistream/Sources/ValistreamCore/{Playlist,Validation,Validation/Rules,Monitoring,Networking,Archive,Segments,Session}/`
- `valistream` executable — CLI, `Valistream/Sources/valistream/`, deps: ValistreamCore + ArgumentParser (swift-argument-parser 1.5.0)
- `ValistreamCoreTests` — `Valistream/Tests/ValistreamCoreTests/` (+ `_setup/Tags.swift`, `Fixtures/`)
- `ValistreamIntegrationTests` — `Valistream/Tests/ValistreamIntegrationTests/Support/`
- swift-tools 6.3, swiftLanguageModes [.v6], platforms macOS 14

## Task→path mapping
tasks.md uses paths like `Sources/ValistreamCore/...` — these are relative to `Valistream/`, so prefix with `Valistream/`.

## Build / test (binding: use xcode-tools MCP)
- Build: `BuildProject` tabIdentifier=`windowtab1`
- Test all: `RunAllTests` tabIdentifier=`windowtab1`; test plan `Valistream-Package`
- Test subset: `RunSomeTests` with `[{targetName, testIdentifier}]` (e.g. `M3U8TokenizerTests` or `M3U8TokenizerTests/handlesCRLF()`)

## IMPORTANT: Serena LSP unavailable for Swift
serena symbol/replace_content/replace_symbol_body tools FAIL: "No language servers available". Use built-in Edit/Write for Swift code edits. Serena memory tools work fine.

## Conventions (binding)
- Code: `styleguide.md` (repo root) — 4-space indent, `else`/`catch` on new line, file header block, MARK order, no Foundation when Swift-native exists.
- Tests: `unit-testing.md` — Swift Testing only, struct suites, `#require` not force-unwrap, `== false` not `!`, area tag per suite from `_setup/Tags.swift`.

## Progress
Phase 1 (T001-T003) done. Phase 2: T004/T006 tokenizer+AttributeList done (14 tests green).

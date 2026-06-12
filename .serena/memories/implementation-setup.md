# Valistream implementation setup

## Layout (after Xcode restructure — June 2026, incl. test relocation)
Workspace `Valistream/Valistream.xcworkspace` (xcode-tools) joins two members:

- **SwiftPM package** -> `Valistream/ValistreamCore/` — builds `ValistreamCore` library + `ValistreamCoreTests` ONLY (no executable, no integration target).
  - `Valistream/ValistreamCore/Sources/ValistreamCore/{Playlist,Validation,Validation/Rules,Monitoring,Networking,Archive,Segments,Session}/`
  - `Valistream/ValistreamCore/Tests/ValistreamCoreTests/` (+ `_setup/Tags.swift`, `_setup/Verifications/`, `Fixtures/`, `Conformance/`, per-module dirs)
  - swift-tools 6.3, swiftLanguageModes [.v6], platforms macOS 14. Only product: `.library(ValistreamCore)`. NO external deps (swift-argument-parser is on the CLI target, not the package).
- **CLI Xcode project** -> `Valistream/Valistream/Valistream.xcodeproj`, TWO targets:
  - `Valistream` (product-type tool, SWIFT_VERSION 6.0). Sources = FileSystemSynchronizedRootGroup at `Valistream/Valistream/Valistream/` (drop files in, no pbxproj edit): `ValistreamCommand.swift` (@main, AsyncParsableCommand), `StatusRenderer.swift`. Built binary name `Valistream` (PRODUCT_NAME=$(TARGET_NAME)); CLI/help invocation name `valistream` (ArgumentParser commandName).
    - Package product deps: `ValistreamCore` (LOCAL — workspace member, XCSwiftPackageProductDependency, NO `package` key) + `ArgumentParser` (REMOTE — XCRemoteSwiftPackageReference swift-argument-parser >=1.5.0, resolved 1.8.2).
  - `ValistreamIntegrationTests` (product-type unit-test bundle, id `no.altibox.tools.ValistreamIntegrationTests`). MOVED here from the package (June 2026). Sources at `Valistream/Valistream/ValistreamIntegrationTests/`: `OneShotSessionTests.swift`, `DeliveryFailureTests.swift`, `PlaceholderTests.swift`, `Support/ScriptedStreamFetcher.swift`, `Support/ManualClock.swift` (the test stubs moved with it).

## Test plans + schemes (NEW June 2026)
Shared folder `Valistream/TestPlans/`, two `.xctestplan` files, each driven by one scheme:
- `ValistreamCore.xctestplan` — testTargets: `ValistreamCoreTests` only (unit/conformance). Referenced by package scheme `ValistreamCore` (`Valistream/ValistreamCore/.swiftpm/xcode/.../ValistreamCore.xcscheme`, ref `container:../TestPlans/ValistreamCore.xctestplan`).
- `Valistream.xctestplan` — testTargets: `ValistreamCoreTests` (containerPath `container:../ValistreamCore`) + `ValistreamIntegrationTests` (CLI proj). targetForVariableExpansion = `Valistream` (CLI tool); carries a live Altibox MPD->HLS URL command-line arg; codeCoverage false. Referenced by CLI scheme `Valistream` (`...Valistream.xcodeproj/xcshareddata/xcschemes/Valistream.xcscheme`, ref `container:../TestPlans/Valistream.xctestplan`).

## Task->path mapping (tasks.md)
- `Sources/ValistreamCore/...` -> `Valistream/ValistreamCore/Sources/ValistreamCore/...`
- `Tests/ValistreamCoreTests/...` -> `Valistream/ValistreamCore/Tests/ValistreamCoreTests/...`
- `Tests/ValistreamIntegrationTests/...` -> `Valistream/Valistream/ValistreamIntegrationTests/...` (CLI proj, NOT package)
- CLI `Sources/valistream/...` -> `Valistream/Valistream/Valistream/` (Xcode target, not the package)

## Build / test (binding: xcode-tools MCP, tab windowtab1)
- Build CLI + its deps: `BuildProject` (builds workspace; resolves packages, compiles ValistreamCore + CLI). Verified green; CLI `--version`->0.1.0, bad URL->exit 2.
- Package lib + unit/conformance tests: `swift test` inside `Valistream/ValistreamCore/` (covers `ValistreamCoreTests` only — integration tests are NOT in the package).
- Integration tests: run via Xcode scheme `Valistream` / `Valistream.xctestplan` (xcode-tools `RunAllTests`/`RunSomeTests` when MCP up). `swift test` does not run them.
- Test subset: `RunSomeTests` [{targetName, testIdentifier}].
- Built CLI binary path: DerivedData `.../Valistream-*/Build/Products/Debug/Valistream`.

## Conventions (binding)
- Code: `styleguide.md` (repo root) — 4-space indent, else/catch on new line, file header block, MARK order, no Foundation when Swift-native exists.
- Tests: `unit-testing.md` — Swift Testing only, struct suites, `#require` not force-unwrap, `== false` not `!`, area tag per suite from `_setup/Tags.swift`.

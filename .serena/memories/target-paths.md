# Target paths: Xcode navigator vs filesystem

Repository root: `/Users/volodymyr.akimenko/Documents/Projects/Valistream`

Use the **filesystem paths** below for Serena, shell commands, patches, worker ownership, and git. Xcode-tools uses the corresponding **navigator paths**.

| Target / area | Filesystem path from repo root | Xcode navigator path |
|---|---|---|
| `ValistreamCore` package root | `Valistream/ValistreamCore/` | `ValistreamCore/` |
| `ValistreamCore` production sources | `Valistream/ValistreamCore/Sources/ValistreamCore/` | `ValistreamCore/Sources/ValistreamCore/` |
| `ValistreamCoreTests` unit/conformance tests | `Valistream/ValistreamCore/Tests/ValistreamCoreTests/` | `ValistreamCore/Tests/ValistreamCoreTests/` |
| `Valistream` CLI production sources | `Valistream/Valistream/Valistream/` | `Valistream/Valistream/` |
| `ValistreamIntegrationTests` Xcode test target | `Valistream/Valistream/ValistreamIntegrationTests/` | `Valistream/ValistreamIntegrationTests/` |
| Xcode project | `Valistream/Valistream/Valistream.xcodeproj/` | project `Valistream` |
| Xcode workspace | `Valistream/Valistream.xcworkspace/` | workspace root |
| Test plans | `Valistream/TestPlans/` | `TestPlans/` |

Critical warning: specs often show paths such as `ValistreamCore/...` and `Valistream/ValistreamIntegrationTests/...`; these are conceptual/Xcode navigator paths, not repo-root filesystem paths. Never create repo-root `ValistreamCore/` or `Valistream/ValistreamIntegrationTests/`. The integration target's real filesystem directory has the doubled component: `Valistream/Valistream/ValistreamIntegrationTests/`.

Before creating a target file, verify with Serena search or XcodeGlob and place it beside existing files for that target.
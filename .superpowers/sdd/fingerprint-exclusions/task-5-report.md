# Task 5 report — remove `AssetItem`, promote `AssetType`

## Where `AssetType` now lives, and why

Kept it in `Sources/HirundoCore/ContentModels.swift`, right where `AssetItem` used to be
(replacing the struct in place). `ContentModels.swift` already holds the other content-model
top-level types (`Page`, `Post`, `ContentItem`), so a bare `public enum AssetType` sits naturally
next to them with zero new files, zero new imports, and the smallest possible diff. A dedicated
file next to the asset code was the alternative the brief allowed, but nothing about `AssetType`
is asset-pipeline-internal — it's a plain value type used as a return type — so there was no
reason to split it out.

## Reference list from Serena, and completeness check

Ran `find_referencing_symbols` on `AssetItem` and on `AssetItem/AssetType` in
`ContentModels.swift`, plus a plain-text `search_for_pattern` for `AssetItem` project-wide as a
cross-check. Full result:

1. `Sources/HirundoCore/AssetPipeline.swift:98` — `AssetPipeline.detectAssetType(for:) -> AssetItem.AssetType`
2. `Sources/HirundoCore/Assets/AssetProcessor.swift:8` — `AssetProcessor.detectAssetType(for:) -> AssetItem.AssetType`
3. `Tests/HirundoTests/AssetPipelineTests.swift:72–76` — five `AssetItem.AssetType.*` literals in `testAssetTypeDetection`
4. `Sources/HirundoCore/ContentModels.swift:79–98` — the `AssetItem` definition itself (including its `init`)

**The brief's list was complete.** No additional live-code reference turned up.

One non-code hit did turn up: `docs/superpowers/plans/2026-09-06-asset-pipeline-fingerprinting.md:1391`
contains a code snippet quoting the pre-refactor signature (`-> AssetItem.AssetType`). This is a
dated planning document capturing a historical snapshot of the code, not user-facing documentation
and not something that compiles — updating it would misrepresent what the plan actually said at
the time it was written, and it falls outside this task's doc scope (README/CLAUDE.md/ARCHITECTURE.md
are Task 7's). Left untouched; flagging it here per the brief's instruction to flag anything the
list didn't mention.

## Changes made

- `Sources/HirundoCore/ContentModels.swift` — deleted `AssetItem` (struct + its `init`); promoted
  its nested `AssetType` to a top-level `public enum AssetType: Equatable, Sendable` with the same
  four cases (`css`, `javascript`, `image(String)`, `other(String)`) and no conformance changes.
- `Sources/HirundoCore/AssetPipeline.swift` — `detectAssetType(for:)` return type
  `AssetItem.AssetType` → `AssetType`.
- `Sources/HirundoCore/Assets/AssetProcessor.swift` — same signature change.
- `Tests/HirundoTests/AssetPipelineTests.swift` — five `AssetItem.AssetType.*` → `AssetType.*`
  (spelling only; the assertions and expected values are unchanged).
- `CHANGELOG.md` — added one `### Removed` bullet under the existing `[Unreleased]` section
  (that section already existed from earlier tasks, so no new heading was created) naming the
  removal of `AssetItem`, the promotion of `AssetType`, and that nothing constructed `AssetItem`.

## Build and test results

- `swift build`: clean, no warnings introduced.
- `swift test`: **640 tests, 0 failures** — same count as the stated baseline.

## Concerns

None. This was a pure rename/move: no stored properties, no logic, no assertion semantics changed.

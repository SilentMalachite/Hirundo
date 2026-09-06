# Task 3 report: wire fingerprint exclusions into the asset pipeline

## What was implemented

Connected the already-existing `AssetFingerprintExclusions` predicate and
`config.assets.fingerprintExclude` to the asset pipeline's single hashing site.

- **Modified** `Sources/HirundoCore/AssetPipeline.swift`:
  - Added a stored property `public var fingerprintExclusions: AssetFingerprintExclusions =
    AssetFingerprintExclusions()`, next to `enableFingerprinting`/`excludePatterns`, with a
    Japanese doc comment.
  - Changed the single hashing condition inside the private `write(_:relativePath:destinationPath:manifest:)`
    from `if enableFingerprinting {` to `if enableFingerprinting && !fingerprintExclusions.excludes(relativePath) {`.
    This is the only place in the pipeline that fingerprints; both the non-stylesheet path and the
    stylesheet path call through it, so the exclusion check covers every asset type uniformly.
    When the condition is false, `outputURL`/`outputRelativePath` stay at their initial values
    (`candidateURL`/`relativePath`), which is the exact same code path already used when
    fingerprinting is off — so "write under the original name, manifest value == key" falls out
    for free, as the brief predicted.
- **Modified** `Sources/HirundoCore/SiteGenerator.swift`: in `configureAssetPipeline()`, added
  `assetPipeline.fingerprintExclusions = AssetFingerprintExclusions(additional: config.assets.fingerprintExclude)`
  right after `assetPipeline.enableFingerprinting = config.features.fingerprint`.

`relativePath` as passed into `write` is confirmed (via `Assets/AssetFileManager.swift:48`) to
already be the static-directory-relative path with `/` separators and no leading slash — exactly
the format `AssetFingerprintExclusions.excludes` expects.

Not touched: `ScaffoldTemplates`, `AssetPruner`, `AssetReferenceRewriter`, documentation.

## TDD evidence

**RED** — added tests before any implementation:

- `Tests/HirundoTests/AssetPipelineTests.swift`: 3 new tests —
  `testExcludedAssetIsWrittenUnderItsOriginalNameAndMapsToItself`,
  `testExcludedAssetDoesNotPreventOrdinaryAssetsFromBeingFingerprinted`,
  `testUserSuppliedFingerprintExcludePatternExemptsAFile`.
- `Tests/HirundoTests/AssetFingerprintIntegrationTests.swift`: added a `static/robots.txt` fixture
  and one new test, `testFingerprintExcludedAssetKeepsItsOriginalName`.

To capture a clean RED (not just a compile error from the not-yet-existing
`fingerprintExclusions` property), the source changes were stashed, the
property-referencing test (`testUserSuppliedFingerprintExcludePatternExemptsAFile`) was
temporarily commented out, and the other three were run:

Command: `swift test --filter "AssetPipelineTests/testExcludedAssetIsWrittenUnderItsOriginalNameAndMapsToItself|AssetPipelineTests/testExcludedAssetDoesNotPreventOrdinaryAssetsFromBeingFingerprinted|AssetFingerprintIntegrationTests/testFingerprintExcludedAssetKeepsItsOriginalName"`

```
Test Case '-[HirundoTests.AssetFingerprintIntegrationTests testFingerprintExcludedAssetKeepsItsOriginalName]' failed (0.153 seconds).
	.../AssetFingerprintIntegrationTests.swift:140: XCTAssertTrue failed - robots.txt が元の名前で出力されていない
	.../AssetFingerprintIntegrationTests.swift:144: XCTAssertEqual failed: ("Optional("robots-fd89345af6aca5da.txt")") is not equal to ("Optional("robots.txt")")
Test Case '-[HirundoTests.AssetPipelineTests testExcludedAssetDoesNotPreventOrdinaryAssetsFromBeingFingerprinted]' failed (0.004 seconds).
	.../AssetPipelineTests.swift:356: XCTAssertEqual failed: ("Optional("robots-fd89345af6aca5da.txt")") is not equal to ("Optional("robots.txt")")
Test Case '-[HirundoTests.AssetPipelineTests testExcludedAssetIsWrittenUnderItsOriginalNameAndMapsToItself]' failed (0.002 seconds).
	.../AssetPipelineTests.swift:326: XCTAssertEqual failed - 除外されたアセットはキー == 値のままであるべき
	.../AssetPipelineTests.swift:327: XCTAssertTrue failed - 除外されたアセットは元の名前で書き出されるべき
Executed 3 tests, with 5 failures (0 unexpected)
```

All three failed for the expected reason: `robots.txt` was being fingerprinted because nothing
consulted the exclusions yet. (The fourth test was confirmed to fail differently — as a compile
error citing the missing `fingerprintExclusions` member — before it was temporarily commented out
for this run; that compile-error RED was observed directly and is not re-transcribed here.)

**GREEN** — restored the property-referencing test and applied the implementation:

Command: `swift test --filter "AssetPipelineTests|AssetFingerprintIntegrationTests"`

```
Test Suite 'AssetFingerprintIntegrationTests' passed ... Executed 4 tests, with 0 failures (0 unexpected)
Test Suite 'AssetPipelineTests' passed ... Executed 16 tests, with 0 failures (0 unexpected)
Test Suite 'Selected tests' passed ... Executed 20 tests, with 0 failures (0 unexpected)
```

## Full suite result

Command: `swift test 2>&1 | tail -10`

```
Test Suite 'HirundoPackageTests.xctest' passed at 2026-09-06 11:36:27.682.
	 Executed 635 tests, with 0 failures (0 unexpected) in 15.871 (15.923) seconds
Test Suite 'All tests' passed at 2026-09-06 11:36:27.683.
	 Executed 635 tests, with 0 failures (0 unexpected) in 15.871 (15.924) seconds
```

Baseline was 631 tests; 635 = 631 + 4 new tests. Exact match. `swift build` is clean.

## Files changed

- `Sources/HirundoCore/AssetPipeline.swift` (modified)
- `Sources/HirundoCore/SiteGenerator.swift` (modified)
- `Tests/HirundoTests/AssetPipelineTests.swift` (modified — 3 new tests appended)
- `Tests/HirundoTests/AssetFingerprintIntegrationTests.swift` (modified — 1 new fixture line, 1 new test)

## Self-review findings

- **Single hashing site**: confirmed by reading the whole of `AssetPipeline.swift` that `write()`
  is the only place `processor.generateFingerprint`/`addFingerprint` are called, and both
  `processNonStylesheet` and `processStylesheet` funnel through it — so CSS, JS, images, and
  plain files are all covered by the one guard.
- **Manifest invariant**: when a file is excluded, the code takes exactly the same branch as when
  `enableFingerprinting == false` (the `if` body is skipped entirely), so `outputRelativePath ==
  relativePath` and `manifest[relativePath] = relativePath` — verified directly by the new tests
  rather than only inferred from reading the code, per the brief's "assert it anyway."
- **No behavior change for configs without `assets:`**: `Assets()` defaults `fingerprintExclude`
  to `[]`, so `AssetFingerprintExclusions(additional: [])` is identical to the zero-arg
  initializer — only the built-in patterns apply, matching pre-Task-3 behavior for any config
  that predates the `assets` block. `features.fingerprint` still defaults to `false`, untouched.
- **Additive-only for `additional`**: not re-implemented here — relied on the already-tested
  `AssetFingerprintExclusions` guarantee that `additional` cannot remove a built-in pattern.
- **Also exercised in the `SiteGenerator` end-to-end path**, not just the unit-level
  `AssetPipeline`, via the new `AssetFingerprintIntegrationTests` case, per the brief.
- **Scope discipline**: grepped the diff — no changes to `ScaffoldTemplates`, `AssetPruner`,
  `AssetReferenceRewriter`, or any documentation file. No test was weakened; all three brief-listed
  scenarios plus the end-to-end one are present with their original strong assertions.
- **Full-suite count**: 631 → 635, exactly +4 (no accidental double-counting, no skipped tests).

## Concerns

None. The change is minimal (7 lines in `AssetPipeline.swift`, 3 lines in `SiteGenerator.swift`)
and isolated to the one call site the brief named.

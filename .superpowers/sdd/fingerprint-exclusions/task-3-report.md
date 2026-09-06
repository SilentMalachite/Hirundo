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

## Fix round 1/5

**Finding (Important):** the third of the brief's three wiring steps —
`config.assets.fingerprintExclude` → `assetPipeline.fingerprintExclusions` at
`SiteGenerator.swift:430-432` — had no test anywhere in the suite.
`testUserSuppliedFingerprintExcludePatternExemptsAFile` was named and commented for a
pattern "supplied through `assets.fingerprintExclude`", but its body set
`pipeline.fingerprintExclusions` directly on an `AssetPipeline` it constructed itself,
never touching `Config`, `Assets`, or `SiteGenerator`. It re-exercised the `write()`
guard that `testExcludedAssetIsWrittenUnderItsOriginalNameAndMapsToItself` already
covered. Deleting `SiteGenerator.swift:430-432` left the full suite green.

**Fix applied:**

1. Added `testConfigSuppliedFingerprintExcludePatternExemptsAFileEndToEnd` to
   `Tests/HirundoTests/AssetFingerprintIntegrationTests.swift`, following the file's
   existing fixture style. It overwrites the `setUp`-provided `config.yaml` with one
   that adds `assets.fingerprintExclude: ["ads.txt"]` (`ads.txt` matches none of the
   built-in patterns), writes `static/ads.txt`, runs a real
   `SiteGenerator(projectPath:).build()`, and asserts:
   - `_site/ads.txt` exists under its original name
   - the on-disk manifest maps `ads.txt` → `ads.txt`
   - `css/style.css` in the same build still gets a hashed name (so the test cannot
     pass merely because fingerprinting as a whole is off)

2. **Verified the new test actually depends on the wiring**, as requested: temporarily
   deleted `SiteGenerator.swift:430-432` and reran just that test.

   Command: `swift test --filter "AssetFingerprintIntegrationTests/testConfigSuppliedFingerprintExcludePatternExemptsAFileEndToEnd"`

   With the wiring lines removed:
   ```
   .../AssetFingerprintIntegrationTests.swift:171: XCTAssertTrue failed - ads.txt が元の名前で出力されていない
   .../AssetFingerprintIntegrationTests.swift:176: XCTAssertEqual failed: ("Optional("ads-8b546c023a3875ca.txt")") is not equal to ("Optional("ads.txt")")
   Executed 1 test, with 2 failures (0 unexpected)
   ```
   Confirmed: the test fails when the wiring is absent. Restored the two lines
   immediately after (`assetPipeline.fingerprintExclusions = AssetFingerprintExclusions(additional: config.assets.fingerprintExclude)`),
   then confirmed `git diff Sources/HirundoCore/SiteGenerator.swift` produced no
   output — the file is byte-identical to the committed version, no residue from the
   experiment.

3. **Renamed the misnamed unit test** rather than dropping it: chose to keep it because
   it still gives fast, `SiteGenerator`/YAML-independent coverage that `write()`'s
   exclusion check consults whatever `AssetFingerprintExclusions` value is set on the
   pipeline, not just the zero-arg built-in-only default (that distinction isn't
   otherwise pinned — every other `AssetPipelineTests` case either uses the default or
   exercises a built-in pattern like `robots.txt`). Renamed
   `testUserSuppliedFingerprintExcludePatternExemptsAFile` to
   `testWriteGuardHonoursANonBuiltInExclusionPattern` and rewrote its comment to state
   plainly that it does not exercise the config-to-pipeline wiring, pointing at the new
   end-to-end test for that.

**Verification:**

Command: `swift test --filter "AssetPipelineTests|AssetFingerprintIntegrationTests" 2>&1 | tail -20`

```
Test Suite 'AssetPipelineTests' passed ... Executed 16 tests, with 0 failures (0 unexpected)
Test Suite 'HirundoPackageTests.xctest' passed ... Executed 21 tests, with 0 failures (0 unexpected)
Test Suite 'Selected tests' passed ... Executed 21 tests, with 0 failures (0 unexpected)
```

Command: `swift test 2>&1 | tail -10`

```
Test Suite 'HirundoPackageTests.xctest' passed at 2026-09-06 12:05:45.311.
	 Executed 636 tests, with 0 failures (0 unexpected) in 15.915 (15.971) seconds
Test Suite 'All tests' passed at 2026-09-06 12:05:45.311.
	 Executed 636 tests, with 0 failures (0 unexpected) in 15.915 (15.972) seconds
```

636 = 635 (previous total) + 1 new test (the rename doesn't change the count).
`swift build` clean.

Committed as `9e59cdfcbb9ac98d98f6ef6e7be582831a5ced02` (`test: cover the
config-to-pipeline fingerprint exclusion wiring end-to-end`).

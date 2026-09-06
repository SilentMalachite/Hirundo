# Task 6 report — close four test gaps

Baseline: HEAD `301d5e6`, `swift build` clean, `swift test` 640/640 (confirmed before starting).
No file under `Sources/` was changed in the final diff — only `Tests/HirundoTests/*.swift`.

## 1. Single-quoted HTML attribute value

`Tests/HirundoTests/AssetReferenceRewriterTests.swift:156` — `testRewritesSingleQuotedAttributeValue`.

```swift
AssetReferenceRewriter.rewriteHTML("<link href='/css/style.css'>", manifest: manifest, inDirectory: "")
// expected: "<link href='/css/style-9f2a1c04b7e3d5a1.css'>"
```

**How I convinced myself it would fail if the branch broke:** I temporarily edited
`AssetReferenceRewriter.rewriteTag` (Sources/HirundoCore/Assets/AssetReferenceRewriter.swift:151)
so the quote check only matched `"`, not `'`. Re-ran the single test: it failed —
`XCTAssertEqual failed: ("<link href='/css/style.css'>") is not equal to
("<link href='/css/style-9f2a1c04b7e3d5a1.css'>")`. With the quote character undetected, the
unquoted-value scan (which stops at whitespace/`>`) swallowed the literal quote characters into
`value`, `manifest.rewrite` didn't match any key, and the tag was emitted unchanged. Reverted with
`git checkout`, confirmed clean.

## 2. `>` inside a quoted attribute value, followed by a rewritable attribute

`Tests/HirundoTests/AssetReferenceRewriterTests.swift:168` —
`testFindsTagEndPastAGreaterThanInAQuotedAttributeValue`.

```swift
AssetReferenceRewriter.rewriteHTML("<a title=\"1 > 2\" href=\"/css/style.css\">", manifest: manifest, inDirectory: "")
// expected: "<a title=\"1 > 2\" href=\"/css/style-9f2a1c04b7e3d5a1.css\">"
```

Uses the brief's own example, with the `>` attribute placed *before* `href` so the hazard is
actually exercised.

**How I convinced myself:** temporarily stripped the quote-tracking out of `findTagEnd`
(Sources/HirundoCore/Assets/AssetReferenceRewriter.swift:89-104) so it just returns the first `>`
regardless of quote state. Re-ran the test: it failed — `XCTAssertEqual failed:
("<a title="1 > 2" href="/css/style.css">") is not equal to
("<a title="1 > 2" href="/css/style-9f2a1c04b7e3d5a1.css">")`. With the naive scan, the tag was
truncated at the `>` inside `title`, `href` fell outside the "tag" as ordinary trailing text, and
was never rewritten. Reverted with `git checkout`, confirmed clean.

## 3. Relative reference resolved from the output root

`Tests/HirundoTests/AssetManifestTests.swift:51` —
`testRewritesRelativeReferenceResolvedFromTheOutputRoot`.

```swift
manifest.rewrite(reference: "images/logo.png", inDirectory: "")
// expected: "images/logo-1b4d0f77c2ae8e93.png"
```

**How I convinced myself:** first tried breaking the `candidate` ternary in
`AssetManifest.rewrite` (collapsing `directory.isEmpty ? path : directory + "/" + path` to always
`directory + "/" + path`) — the test still passed, because `normalize` drops leading empty path
segments, so this particular mutation is not observable through this branch (worth noting: it
means that half of the ternary is redundant, not that the test is weak — see "did not behave as
predicted" below). I then tried a more targeted, plausible bug: treating an empty `directory` the
same as a root-relative reference by returning `"/" + value + suffix` when `directory.isEmpty`
(Sources/HirundoCore/Assets/AssetManifest.swift:55-58). That failed exactly this new test —
`XCTAssertEqual failed: ("Optional("/images/logo-1b4d0f77c2ae8e93.png")") is not equal to
("Optional("images/logo-1b4d0f77c2ae8e93.png")")` — while all 18 pre-existing `AssetManifestTests`
kept passing, confirming only this new test guards that confusion. Reverted with `git checkout`,
confirmed clean.

## 4a. JavaScript is hashed over its minified bytes

`Tests/HirundoTests/AssetPipelineTests.swift:307` —
`testJSFingerprintCoversTheMinifiedBytesNotTheSource`.

Builds the same JS source (`function greet() { console.log("hello"); }`) twice — once with
`jsOptions.minify = false`, once with `true` — and asserts the two manifest entries for `app.js`
differ, then re-hashes the bytes actually written to disk for the minified build and asserts the
emitted filename contains that hash.

**How I convinced myself:** temporarily made `processNonStylesheet`
(Sources/HirundoCore/AssetPipeline.swift:138-139) write `Data(content.utf8)` (the raw source)
instead of `Data(processor.processJS(content, options: jsOptions).utf8)` — i.e. simulating "the
minify option is silently ignored, so nothing ever changes". Re-ran the test: it failed —
`XCTAssertNotEqual failed: ("Optional("app-bfdd174f797f7c16.js")") is equal to
("Optional("app-bfdd174f797f7c16.js")") - 最小化でバイト列が変わったのにハッシュが同じなのは、
ソースをハッシュしている証拠`. Reverted with `git checkout`, confirmed clean.

## 4b. The unresolved-stylesheet warning fires

`Tests/HirundoTests/AssetFingerprintIntegrationTests.swift:242` —
`testUnresolvedCSSToCSSImportWarnsOnStderr`. Added next to
`testNonUTF8FileInOutputTreeIsSkippedAndWarnedAbout`, reusing that file's private
`capturingStandardError` helper (no second stderr-capture helper written).

Overwrites the fixture's `static/css/style.css` with an unresolvable `@import
url("other.css");`, runs `SiteGenerator.build()` under `capturingStandardError`, and asserts the
captured stderr names both the file (`css/style.css`) and the unresolved reference (`other.css`).

**How I convinced myself:** temporarily deleted the `for reference in
result.unresolvedStylesheetReferences { warn(...) }` loop in `processStylesheet`
(Sources/HirundoCore/AssetPipeline.swift:171-174). Re-ran the test: it failed both assertions —
`XCTAssertTrue failed - 警告がファイルを名指ししていない:` and `XCTAssertTrue failed -
警告が未解決の参照を名指ししていない:` (both with empty captured stderr). Reverted with
`git checkout`, confirmed clean.

## Commands and final result

```
$ swift build            # Build complete! (clean)
$ swift test             # Executed 645 tests, with 0 failures (0 unexpected)
```

640 baseline + 5 new tests (2 in AssetReferenceRewriterTests, 1 in AssetManifestTests, 1 in
AssetPipelineTests, 1 in AssetFingerprintIntegrationTests) = 645. All new tests pass in their
correct (unmutated) state; all four were also confirmed RED against a plausible break of their
named branch, then reverted via `git checkout` before the final build/test run. `git status`
after the run shows no changes under `Sources/`, only the four test files under `Tests/`.

## Anything that did not behave as the brief predicted

Item 3's first mutation attempt (collapsing the `directory.isEmpty ? path : …` ternary in
`AssetManifest.rewrite`'s `candidate` computation) did **not** turn the new test red, because
`AssetManifest.normalize` splits with `omittingEmptySubsequences: true` and so silently discards
the resulting leading empty path segment (`"" + "/" + "images/logo.png"` normalizes identically to
`"images/logo.png"`). That specific half of the ternary is therefore currently redundant dead
weight rather than a load-bearing branch — it is not a bug (behavior is unchanged either way), just
a piece of the code that turned out to be less critical than the brief's phrasing suggested. The
part of this code path that actually matters, and that the added test does guard, is the final
`relativePath(from: directory, to: value)` call for an empty `directory` — confirmed red against
the more plausible "empty directory treated like root-relative" mutation described above. No
source change was made; this is reported as an observation, not a fix.

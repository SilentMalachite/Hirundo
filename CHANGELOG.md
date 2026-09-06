# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- **SECURITY**: `hirundo serve` now screens the `/livereload` WebSocket handshake before upgrading the connection: `Host` must be an IP literal or `localhost`, and `Origin` must be an http(s) URL whose host and port match it. This blocks cross-site WebSocket hijacking by another page open in the developer's browser, and DNS rebinding past that origin check. Refusals return `403` and print a sanitized reason to stderr, repeated only when the reason changes so a refused browser's endless reconnecting reports itself once
- Note: the check is not authentication. There is no token and no configuration — `config.yaml` is unchanged — and anyone who can reach the port can still read the served site

### Fixed
- `AssetPruner.prune` reported a `static/` directory (or the output directory) it could not read as "nothing to prune" instead of failing, turning a permission problem or a vanished directory into silence. Both call sites now propagate the failure, and `SiteGenerator` reports it as a `.writing` build error
- The reference-rewriting pass over the output tree silently skipped a file whose attributes it could not read, and one that was not valid UTF-8. Both cases now print a one-line warning to stderr naming the file, matching the shape of the asset pipeline's own warnings
- A pass-through asset (anything not CSS or JS) is now copied to its destination with `FileManager.copyItem` instead of being read fully into memory and rewritten byte-for-byte, so the output keeps the source file's permissions and extended attributes, and APFS can clone the file instead of duplicating its bytes
- **File watching**: an atomic save — how every Cocoa editor, and `String.write(to:atomically:)`, writes a file — reports two paths to FSEvents: the real file and a scratch file named `<name>.sb-<hex>-<random>` that is renamed away microseconds later. `HotReloadManager` reported both, so each save counted as two changes to a file that no longer exists, and a user's own ignore pattern could not suppress it (`*.tmp` does not match `notes.tmp.sb-…`). The scratch file is now recognized and dropped. `hirundo serve` was shielded from the visible symptom by its debounce and by `RebuildCoordinator` collapsing requests, but `HotReloadManager` is public API and the six `HotReloadManagerTests` failures this caused were the only red in the suite
- **CRITICAL**: `buildWithRecovery` skipped everything after page rendering — static assets, archive/category/tag pages, and the `sitemap` / `rss` / `searchIndex` feature outputs — while reporting success. `hirundo serve` uses that path for its initial build *and* every rebuild, so the development server served a site with no CSS and no blog index pages; `hirundo build --continue-on-error` produced the same partial output. Both build paths now run one shared list of finalization steps, and a step that fails is reported as a `writing` error instead of being skipped silently
- A `features:` or `limits:` block had to spell out **all** of its keys — the synthesized decoder required every one — so `features: {sitemap: true}` failed the whole parse. Each key now defaults independently, as the documentation always said
- Configuration errors named no key: any structural problem surfaced as `Failed to parse configuration: The data couldn't be read because it is missing.` Errors now report the coding path (`Missing required field: site.url`, `Invalid configuration value: blog.postsPerPage: expected Int`), a validation error raised by a model is no longer reported as invalid YAML, and a genuine YAML error keeps the parser's own line, column and caret (a duplicated block now says which key was duplicated)
- `HirundoConfig.load` re-wrapped a `ConfigError` that `parse` had already produced, reporting it as a parse failure whatever it actually was — and prefixing "Failed to parse configuration:" twice when it genuinely was one
- **CRITICAL**: fingerprinting hashed the **source** bytes while writing the **processed** ones, so the hash did not identify the file it named — toggling `features.minify` left the hash unchanged, so two outputs that differed only in whether they were minified could collide on the same name. The hash is now always taken over the final output bytes; because a CSS file's final bytes are not known until after its `url(...)` references are rewritten, asset processing runs in two passes, non-CSS first and then CSS
- The manifest's values were bare filenames with the directory dropped (`style-abc.css`), which made them useless for rewriting references. They are now paths relative to the output directory (`css/style-abc.css`)

### Added
- `hirundo validate` — checks `config.yaml` without building. Undecodable configurations exit non-zero naming the key at fault; keys Hirundo does not act on (a typo, or a block that was never wired up such as `timeouts` or `server.cors`) are reported as warnings and exit 0. Keys are checked at the top level and one level in, with a "Did you mean …?" suggestion for near misses. Error messages have suggested this command for some time; it did not exist until now
- `features.fingerprint` — adds a content hash to asset names and rewrites the generated HTML's `href` / `src` / `srcset`, CSS `url(...)`, `<style>` bodies, and `style` attributes to match. The mapping is written to `_site/asset-manifest.json`. Output from older hashed names is removed on every build, so `hirundo serve`'s non-clean rebuilds do not grow the output without bound. Strings inside JavaScript and a CSS-to-CSS `@import url(...)` are not rewritten (the latter prints a warning)
- Fingerprint exclusions. `robots.txt`, `favicon.ico`, `CNAME`, `_headers`, `_redirects`, `.htaccess`, and everything under `.well-known/` are now excluded from `features.fingerprint` unconditionally, with no configuration needed — each is fetched under a fixed, well-known name that no page references, so renaming it served it only under a hash and turned every request for the well-known name into a 404. A new top-level `assets:` block adds more patterns via `assets.fingerprintExclude`, which only add to the built-in list and cannot remove one of them. A pattern with no `/` matches the file name at any depth (`ads.txt` matches `vendor/ads.txt`); one with a `/` matches the whole relative path (`css/style.css` does not match `deep/css/style.css`); `*` matches within one path segment and never crosses `/`; `**` as a whole segment matches any number of segments including zero; everything else is literal, matching is case-sensitive, and there is no `?`, character class, escaping, or negation. An excluded asset is written under its original name and appears in the manifest mapped to itself, so references to it keep working and the pruner does not treat it as stale

### Changed
- **BREAKING**: `site` and `author` are now validated when read from `config.yaml`. They were the only models whose throwing initializer the decoder bypassed, so the documented rules — URL format, title/description length, language code format, e-mail format — did not apply to a configuration file. A `config.yaml` that violates them now fails the build instead of being accepted silently
- **BREAKING**: `limits` values must be positive integers. `maxMarkdownFileSize: 0` previously made every Markdown file "too large" with an error that mentioned neither the limit nor the configuration
- **BREAKING**: the `site.*` length caps now come from `limits` instead of being hardcoded, so `maxTitleLength`, `maxDescriptionLength`, `maxUrlLength`, `maxAuthorNameLength`, `maxEmailLength` and `maxLanguageCodeLength` finally do something. `maxLanguageCodeLength` defaults to 35 rather than 10, which is what a well-formed BCP 47 tag such as `nan-Hant-TW` needs
- **BREAKING**: `limits.maxConfigFileSize` was removed. A file's own size cap cannot be read out of that same file, so it is now the constant `Limits.maxConfigFileSize` (1 MB) — and it is actually applied: `HirundoConfig.load` previously had no size guard at all. The read is bounded rather than the size measured, so a symlinked `config.yaml` cannot slip past it
- `limits` is now decoded before the blocks it governs, so a broken limit is reported before the `site` error it would have caused
- **BREAKING**: the `build.enableAssetFingerprinting`, `enableSourceMaps`, `concatenateJS` and `concatenateCSS` keys were removed. They decoded into `Build` and were read by nothing. Even wired up, each was broken in its own way: the fingerprint hashed the source bytes while writing the processed ones, so the hash did not identify the file it named; the concatenation matcher disagreed with its own file finder, so a `js/*.js` rule emitted the bundle *and* the sources while a bare `*.js` rule dropped the sources entirely; and no source map was generated by any code path. `hirundo validate` reports these keys if a configuration still carries them. Fingerprinting was later reimplemented correctly as `features.fingerprint`, with the reference rewriting these keys never had (see Added below); concatenation and source maps were not brought back (see Removed below)
- docs: README/README.ja/CLAUDE/ARCHITECTURE/SECURITY/AGENTS describe the live-reload handshake check and no longer say `/livereload` accepts connections directly
- docs: README/README.ja no longer claim `limits` is all-or-nothing, and CLAUDE.md no longer describes `minify` as minifying HTML (it covers CSS and JS assets only)

### Removed
- **BREAKING**: removed `AssetConcatenator` and `AssetConcatenationRule`, along with `AssetPipeline.concatenationRules` and `enableSourceMaps`, `CSSProcessingOptions.sourceMap`, `JSProcessingOptions.sourceMap` / `transpile` / `target`, and `AssetFileManager.findFiles`. All of these were library-level surface unreachable from `config.yaml`: concatenation's rule matching disagreed with its own file finder (a `js/*.js` rule bundled the files *and* still emitted the originals, while a bare `*.js` rule dropped the originals entirely), no source map was ever produced by any code path, and `transpileJS` printed a warning and returned its input unchanged. Use Babel or esbuild for ES6+ transforms
- **BREAKING**: `AssetPipeline.processAssets` / `saveManifest` / `loadManifest` now work with `AssetManifest` instead of `[String: String]`. `AssetProcessor.processAssetContent` (process-and-write) was removed; writing is now `AssetPipeline`'s responsibility
- **BREAKING**: removed the unused `destinationPath` and `concatenationRules` parameters from `AssetFileManager.processDirectory`
- **BREAKING**: removed `AssetItem`. Nothing in the codebase constructed it — its stored properties (`sourcePath`, `outputPath`, `processed`, `metadata`) were unreachable dead weight — so only its nested `AssetType` enum was ever actually used, and only as a return type. `AssetType` is now a top-level `public enum` in `ContentModels.swift`; every reference to `AssetItem.AssetType` becomes `AssetType`

## [1.1.4] - 2025-10-28

### Changed
- **CONCURRENCY**: Improved Swift 6 concurrency compliance across core components
- **PERFORMANCE**: Replaced DispatchQueue barrier pattern with NSLock in TemplateEngine for simpler synchronization
- **SIMPLIFICATION**: Removed PathSanitizer cache, converting it to enum-based pure function
- **CI**: Fixed ThreadSanitizer configuration to properly handle external library warnings

### Added
- **TYPE SAFETY**: Added Sendable conformance to markdown processing components (MarkdownParser, ContentProcessor, FrontMatterProcessor, MarkdownValidator, MarkdownNodeProcessor, HTMLRenderer, StreamingMarkdownParser)
- **TYPE SAFETY**: Added Sendable conformance to HTMLSanitizer

### Technical Details
- All changes maintain thread safety while ensuring Swift 6 strict concurrency compliance
- Tests pass and ThreadSanitizer reports no data races in Hirundo code
- Note: TSan warnings from swift-markdown library are expected and documented in CI configuration

## [1.1.3] - 2025-10-28

### Fixed
- **CRITICAL**: Fixed Swift 6 concurrency issue in ServeCommand with sendable closure captures
- **RELIABILITY**: Fixed ConfigError propagation to properly handle missingRequiredField validation errors

### Changed
- docs: Updated platform requirements to reflect macOS 12+ only (removed Linux references)
- ci: Configure ThreadSanitizer to report but not fail on data races from external libraries

## [1.1.0] - 2025-08-31

### Added
- docs: DEVELOPMENT.md with local workflows and conventions
- docs: TESTING.md with structure, coverage expectations, and fixture usage
- features: Built-in sitemap/RSS/search-index/minify now configured via `features:` in `config.yaml`

### Changed
- docs: README now links to documentation index and Japanese README
- docs: ARCHITECTURE diagram labels cleaned up for clarity
- docs: CONTRIBUTING explicitly documents Conventional Commits and pre-PR checklist
- docs: README/README.ja/SECURITY reflect `features:` instead of `plugins:`
- cli: `build`/`serve` を `HirundoCore` に委譲し本実装へ移行（`AsyncParsableCommand` 化、フラグ反映、待機ループの非同期化）
- ci: GitHub Actions を Swift 6.0 + macOS ランナーに統一
- devserver: `/auth-token` の JSON 応答生成を `JSONSerialization` へ変更（安全性/保守性の向上）
- cli: `build --config <file>` で任意ファイル名の設定を正式サポート（`SiteGenerator.init(configURL:)` を追加）

### Removed
- **BREAKING**: Removed complex security features that were over-engineered for a static site generator
- **BREAKING**: Removed TimeoutManager and timeout configuration (simplified to basic file operations)
- **BREAKING**: Removed CORS configuration and WebSocket authentication (simplified development server)
- **BREAKING**: Removed plugin system (Plugin/PluginManager); use built-in features under `features:` instead
- **BREAKING**: Removed SecurityValidator, FileSecurityUtilities, and AssetSecurityManager
- **BREAKING**: Removed complex path validation and DoS attack protection features
- **BREAKING**: Removed WebSocketAuthManager, CORSManager, StaticFileHandler, and WebSocketManager

### Simplified
- Configuration is now much simpler with only essential settings
- Development server focuses on basic static file serving and live reload
- File operations use standard Swift APIs without complex validation layers
- Template rendering simplified to basic Stencil functionality
- Removed over 30,000 lines of unnecessary security-related code

## [1.0.3] - 2025-08-28

### Added
- cli: `build --config <file>` で任意ファイル名の設定ファイルに対応（`SiteGenerator.init(configURL:)` を追加）

### Changed
- cli: `build`/`serve` を `HirundoCore` に委譲し本実装へ移行（`AsyncParsableCommand` 化、フラグ反映、非同期待機ループ）
- cli: ルートコマンドを非同期対応（`AsyncParsableCommand` + availability）にし、実行性を改善
- ci: GitHub Actions を Swift 6.0 + macOS ランナーに統一
- devserver: `/auth-token` の JSON 応答生成を `JSONSerialization` へ変更（安全性/保守性の向上）

### Security
- devserver: 認証トークン生成を `SecRandomCopyBytes` に変更（暗号学的強度の確保）
- devserver: CORS オリジン照合の `NSRange` を `NSRange(origin.startIndex..., in:)` に修正（UTF-16 境界の不整合を解消）

### Fixed
- cli: 非同期ルート検査の警告解消（availability 付与）

### Security
- devserver: 認証トークン生成を `arc4random_uniform` から `SecRandomCopyBytes` に変更（暗号学的強度の確保）
- devserver: CORS オリジン照合の `NSRange` を `NSRange(origin.startIndex..., in:)` に修正（UTF-16 境界の不整合を解消）

### Fixed
- cli: `serve` 実装で `RunLoop.main.run()` を非同期文脈から呼べない問題を回避（非同期待機ループへ置換）

## [1.0.1] - 2025-08-26

### Added
- Development server: token-based WebSocket authentication flow with `/auth-token` endpoint and CORS headers

### Changed
- Streaming markdown parser: front matter extraction is now byte-accurate to avoid multibyte offset drift
- Template renderer cache: stable SHA256-based cache keys; dependency-based invalidation

### Fixed
- Plugin system: ensure plugins are initialized so hooks run (`initializeAll(context:)` wired in `SiteGenerator`)
- Security: `isPathSafe` now verifies exact base or subpath (boundary-aware check)

### Added
- **NEW**: Comprehensive EdgeCase test suite (85+ tests) for robust error handling
- **NEW**: SecurityValidator tests for enhanced security validation  
- **NEW**: Integration tests for end-to-end workflow validation
- **NEW**: MemoryEfficientCacheManager for optimized memory usage
- **NEW**: StringExtensions utility for common string operations
- Enhanced WebSocket authentication system with complete token management
- Comprehensive security improvements and vulnerability fixes
- Configurable security and performance limits through `Limits` configuration
- Advanced path traversal protection with symlink resolution
- Memory-safe WebSocket session management with automatic cleanup
- Real-time error reporting in development server
- Unified error handling system with detailed error categorization
- Safe CSS/JS processing with validation before minification
- Enhanced file system monitoring with FSEvents on macOS
- Multi-level caching system with intelligent invalidation
- Plugin system security validation and safe loading
- Template engine thread safety improvements
- Comprehensive timeout configuration for all I/O operations
- CORS (Cross-Origin Resource Sharing) support for development server
- **Swift 6.0** full concurrency support and compliance

### Changed
- **BREAKING**: Upgraded to Swift 6.0 with full concurrency support
- **SECURITY**: Improved SecurityValidator to handle absolute paths within project directories
- **PARSER**: Enhanced MarkdownParser front matter parsing for edge cases (files ending with `---`)
- **ERROR HANDLING**: Refactored ContentProcessor with better error handling for invalid UTF-8 files
- **RELIABILITY**: Updated force unwrapping (`try!`) to proper error handling in Config.swift
- **PERFORMANCE**: Optimized PathSanitizer for better performance and thread safety
- **BREAKING**: JavaScript transpilation disabled by default for security reasons
- Improved HTML rendering using proper AST-based processing
- Enhanced markdown parser with better security validation
- Strengthened asset pipeline with comprehensive path sanitization
- Template engine now uses thread-safe environment updates
- Development server error handling improved with detailed logging

### Fixed
- **CRITICAL**: Fixed path traversal vulnerabilities in SecurityValidator  
- **CRITICAL**: Removed dangerous force unwrapping operations
- **CRITICAL**: Resolved Swift 6.0 concurrency issues and warnings
- **RELIABILITY**: Improved error type consistency across the codebase
- **TESTING**: Fixed all failing edge case tests including UTF-8 and front matter parsing
- **MEMORY**: Enhanced memory management in WebSocket connections
- FSEventsWrapper implementation completed and thread-safe
- Template engine race conditions resolved
- Memory leaks in WebSocket management eliminated
- Asset processing file conflicts resolved
- Plugin loading system security issues addressed
- Build system compatibility issues resolved

### Security
- **CRITICAL FIX**: Strengthened path validation to prevent directory traversal attacks
- **ENHANCED**: HTML content sanitization in MarkdownParser with dangerous pattern detection
- **IMPROVED**: File permission and access control validation
- **ADDED**: Comprehensive input validation for all user-provided content
- **SECURED**: Plugin system with proper sandboxing (dynamic loading disabled for security)
- Comprehensive input validation and sanitization
- Safe handling of user-generated content
- Memory-safe resource management
- XSS prevention in HTML rendering
- DoS attack prevention through configurable timeouts
- WebSocket authentication and session management
- CORS policy enforcement for secure cross-origin requests

### Performance
- **NEW**: Memory-efficient caching system implementation
- **IMPROVED**: Concurrent file processing with proper error recovery
- **ENHANCED**: Streaming markdown parser for large files
- **OPTIMIZED**: Asset pipeline performance with better minification

### Developer Experience
- **NEW**: 85+ comprehensive tests now passing (previously had failures)
- **IMPROVED**: Enhanced error messages with actionable feedback
- **ENHANCED**: Development server with better hot reload capabilities
- **ADDED**: Proper configuration validation with detailed error reporting

### Migration Notes
⚠️ **Important**: This release includes breaking changes due to Swift 6.0 upgrade
- Ensure Swift 6.0+ is installed
- Review custom plugins for concurrency compliance  
- Test thoroughly before production deployment
- Update CI/CD pipelines for Swift 6.0 compatibility

## [1.0.0] - 2025-08-17

### Added
- Initial release of Hirundo static site generator
- Swift-based high-performance static site generation
- Markdown support with frontmatter using swift-markdown
- Stencil-based templating engine
- Live reload development server
- Plugin architecture with built-in plugins
- Multi-level caching system
- Type-safe configuration system

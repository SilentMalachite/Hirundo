# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.3] - 2025-10-28

### Fixed
- **CRITICAL**: Fixed Swift 6 concurrency issue in ServeCommand with sendable closure captures
- **RELIABILITY**: Fixed ConfigError propagation to properly handle missingRequiredField validation errors

### Changed
- docs: Updated platform requirements to reflect macOS 12+ only (removed Linux references)

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

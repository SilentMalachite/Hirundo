# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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

### Changed
- **BREAKING**: JavaScript transpilation disabled by default for security reasons
- Improved HTML rendering using proper AST-based processing
- Enhanced markdown parser with better security validation
- Strengthened asset pipeline with comprehensive path sanitization
- Template engine now uses thread-safe environment updates
- Development server error handling improved with detailed logging

### Fixed
- FSEventsWrapper implementation completed and thread-safe
- Template engine race conditions resolved
- Path traversal vulnerabilities patched
- Memory leaks in WebSocket management eliminated
- Asset processing file conflicts resolved
- Plugin loading system security issues addressed
- Build system compatibility issues resolved

### Security
- Comprehensive input validation and sanitization
- Protection against path traversal attacks
- Safe handling of user-generated content
- Memory-safe resource management
- Secure plugin loading with validation
- XSS prevention in HTML rendering

## [1.0.0] - TBD

### Added
- Initial release of Hirundo static site generator
- Swift-based high-performance static site generation
- Markdown support with frontmatter using swift-markdown
- Stencil-based templating engine
- Live reload development server
- Plugin architecture with built-in plugins
- Multi-level caching system
- Type-safe configuration system
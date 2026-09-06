# Hirundo Architecture

This document provides an overview of Hirundo's architecture, design principles, and implementation details.

## Overview

Hirundo is built with a modular, clean architecture that prioritizes performance, maintainability, and simplicity.

```
┌─────────────────────────────────────────────────────────────┐
│                        Hirundo CLI                          │
│                     (ArgumentParser)                        │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                        HirundoCore                          │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌──────────────────┐ │
│  │ SiteGenerator │  │ TemplateEngine│  │ DevelopmentServer│ │
│  └───────────────┘  └───────────────┘  └──────────────────┘ │
│  ┌───────────────┐  ┌───────────────┐  ┌──────────────────┐ │
│  │ MarkdownParser│  │ AssetPipeline │  │ HotReloadManager │ │
│  └───────────────┘  └───────────────┘  └──────────────────┘ │
│  ┌───────────────┐  ┌───────────────┐  ┌──────────────────┐ │
│  │SiteScaffolder │  │   FSEvents    │  │  Error Handling  │ │
│  └───────────────┘  └───────────────┘  └──────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Site Generator (`SiteGenerator.swift`)

The central orchestrator responsible for:
- Content discovery and parsing
- Template rendering
- Asset processing
- Output generation
- Built-in feature generation (sitemap, RSS, search index)

**Key Features:**
- Batched concurrent content processing (`withThrowingTaskGroup` in `ContentProcessor`)
- Template caching
- Error recovery (`buildWithRecovery`)
- Progress reporting

### 2. Markdown Parser (`MarkdownParser.swift`)

Handles markdown content processing using Apple's swift-markdown:
- Frontmatter extraction and validation
- AST-based HTML rendering
- Security validation
- Content analysis

**Security Features:**
- Content size validation
- Path traversal protection
- Safe YAML parsing
- Input sanitization

### 3. Template Engine (`TemplateEngine.swift`)

Stencil-based templating with enhanced features:
- Thread-safe template caching
- Custom filter registration
- Site-aware configuration
- Environment isolation

**Thread Safety:**
- Concurrent read access
- Barrier write operations
- Safe environment updates

### 4. Asset Pipeline (`AssetPipeline.swift`)

Processes static assets with security focus:
- CSS/JS minification with validation
- Path sanitization
- File type validation
- Content fingerprinting with HTML/CSS reference rewriting

`features.minify`, `features.fingerprint`, and `assets.fingerprintExclude` are the
asset-related settings reachable from `config.yaml`. Enabling fingerprinting names each
non-excluded asset `<name>-<hash>.<ext>`, where `<hash>` is the first 16 lowercase hex
digits of a SHA-256 over the asset's *final* output bytes — for CSS, that means after
minification and after its own `url(...)` references are rewritten, which is why asset
processing runs in two passes (non-CSS, then CSS). The generated HTML's `href` / `src` /
`srcset`, CSS `url(...)`, `<style>` bodies, and `style` attributes are rewritten to the
hashed names; the mapping is written to `_site/asset-manifest.json`, and output from a
previous build's hashed names is pruned on every build (a `static/` subdirectory the pruner
cannot read is now a build error rather than a silent no-op).

`AssetFingerprintExclusions` (`Assets/AssetFingerprintExclusions.swift`) keeps fingerprinting
from renaming a file that is fetched under a fixed, well-known name no page ever references —
`robots.txt`, `favicon.ico`, `CNAME`, `_headers`, `_redirects`, `.htaccess`, and everything
under `.well-known/` are excluded unconditionally. `assets.fingerprintExclude` adds glob-like
patterns to that list (a pattern with no `/` matches the file name at any depth; one with `/`
matches the whole relative path; `*` matches within one path segment; `**` as a whole segment
matches zero or more segments) and cannot remove a built-in. An excluded asset is written
under its original name and mapped to itself in the manifest, so it is never treated as stale
output by the pruner.

Two references are not rewritten: a string inside JavaScript (not statically
distinguishable from a reference) and a CSS-to-CSS `@import url(...)` (its target's hash is
not yet known when the importing stylesheet is processed; this prints a warning). A
pass-through asset (anything not CSS or JS) is copied to its destination with
`FileManager.copyItem` rather than read fully into memory and rewritten byte-for-byte, so the
output keeps the source's permissions and extended attributes, and APFS can clone the file
instead of duplicating its bytes; fingerprinting such a file streams it through SHA-256
instead of loading it whole. Asset concatenation and source map generation have been removed
entirely — `AssetConcatenator`, `AssetPipeline.enableSourceMaps`, and the `sourceMap` option
no longer exist.

**Security Measures:**
- Path traversal prevention
- Safe processing validation
- Symlink resolution
- Content verification

### 5. Development Server (`DevelopmentServer.swift`)

Serves the build output over HTTP, with a WebSocket live-reload channel:
- Static file serving from the output directory
- File system watching
- Live reload functionality
- Error reporting
- Memory management

**Features:**
- FSEvents (macOS)
- WebSocket session cleanup
- Real-time error notifications
- Request logging

**Routing:** the `/livereload` WebSocket route is registered first, and static
files are served from `HttpServer.notFoundHandler` so they only run after the
explicit routes have had their chance. Swifter's router matches literal path
segments and `:name` variables — it does not interpret regular expressions — so
a catch-all route cannot be expressed as `/(.*)`.

**Handshake screening:** `WebSocketOriginGuard` (`Serve/WebSocketOriginGuard.swift`)
decides every `/livereload` handshake before Swifter upgrades the connection,
because after the upgrade there is no response left to refuse with. It accepts a
request only when `Host` names an IP literal or `localhost` — a name means a
resolver chose where the connection went, which is how DNS rebinding defeats an
origin check on its own — and when `Origin` is an http(s) URL whose host and port
equal that `Host`. Schemes are not compared — an `https` origin is accepted when it
names the same host and port, which covers a TLS terminator that preserves the port
— but a proxy on the default 443 will not match a plain-HTTP `Host`, so running the
server behind one is not supported. This is a deliberate departure from RFC 6454,
where an origin is scheme, host and port; the scheme is the part this server cannot
observe about itself. A refusal writes one sanitized line to stderr (control
characters stripped, 80 characters max, since the header values are attacker
supplied) and returns `403`. The guard takes no configuration: relaxing either rule
would be reintroducing the attack it stops. It is a same-origin check and not
authentication — there is no token and no identity involved.

`resolveFilePath(forRequestPath:)` maps a request to a file: directory requests
(`/`, `/about`, `/about/`) resolve to that directory's `index.html`, and any
path that standardizes outside the output directory is rejected.

### 6. Built-in Features

Hirundo provides built-in features (no dynamic loading) that participate in the build:
- Sitemap generation
- RSS feed creation
- CSS/JS minification
- Search index generation
- Asset fingerprinting with HTML/CSS reference rewriting

Configure these under `features:` in `config.yaml`. Each is a plain boolean
(`sitemap`, `rss`, `searchIndex`, `minify`, `fingerprint`), all defaulting to
`false`. Note that `minify` sets `minify` on the CSS and JS asset options
together; there is no HTML minification and no separate per-language toggle.

### 7. Site Scaffolder (`Scaffold/`)

Backs `hirundo init`:
- `SiteScaffolder.swift` — creates the site tree and reports each written path
- `ScaffoldTemplates.swift` — the file bodies it writes
- `InitDestinationResolver.swift` — resolves and validates the destination path

An existing `.gitignore` is merged rather than overwritten (including under
`--force`); merged files are reported as `📝 Updated <path>` instead of created.
An empty destination path is rejected, and directories created during a run
that fails partway are rolled back.

## Security Architecture

### Basic Security Measures

- Input validation for configuration files
- Safe file operations with proper error handling
- Memory-safe resource management
- WebSocket session cleanup
- Development server requests that escape the output directory are rejected

### File Operations

- Standard Swift file operations with error handling
- Proper resource cleanup
- Safe path handling

## Performance Architecture

### Caching Strategy

One cache is wired into the build today: templates.

```
┌────────────────────────────────┐
│  Template Cache                │
│  Templates/TemplateCache*      │
│                                │
│ • Loaded template sources      │
│ • Used by SiteTemplateRenderer │
└────────────────────────────────┘
```

`MemoryEfficientCacheManager.swift` implements the general size-bounded cache with
dependency-based invalidation that backs it: `Templates/TemplateCacheManager.swift`
owns an instance, and `SiteTemplateRenderer.getCacheStatistics()` surfaces its
statistics. Templates are its only client. There is no parsed-content cache and no
rendered-page cache; every build reparses and rerenders content. Multi-level caching
and incremental rebuilds remain future work (see below).

### Parallel Processing

- Concurrent content parsing — `ContentProcessor` processes files in batches via
  `withThrowingTaskGroup` / `withTaskGroup`
- Async I/O operations throughout the build (`SiteGenerator.build` is `async`)

Asset processing is currently sequential, and there is no worker-pool
abstraction.

## Configuration System

### Type-Safe Configuration

`HirundoConfig` decodes exactly seven top-level keys. Unknown keys are silently
ignored.

```swift
HirundoConfig
├── site     (required)
├── build    (optional, defaults)
├── server   (optional, defaults)
├── blog     (optional, defaults)
├── features (optional, all false)
├── limits   (optional, defaults)
└── assets   (optional, fingerprintExclude: [])
```

Notable absences, so they are not looked for: there is no `plugins` block (the
plugin system was removed — `features` replaces it), no `timeouts` block, and
no CORS or WebSocket-authentication configuration. The live-reload handshake
check described above is likewise unconfigurable and has no keys. `server`
decodes only `port` (default `8080`) and `liveReload` (default `true`).

### Validation Pipeline

1. **Syntax Validation**: YAML parsing
2. **Type Validation**: Codable conformance
3. **Semantic Validation**: Business rules
4. **Security Validation**: Limits and constraints

## Error Handling

### Unified Error System

```swift
HirundoError Protocol
├── Category (enum)
├── Code (string)
├── Details (string)
├── Underlying Error
├── User Message
└── Debug Info
```

`HirundoErrorInfo` is the concrete conforming type. It adds an optional
per-error `suggestion`; `suggestedAction` returns that suggestion when present
and otherwise falls back to the category's default advice.

### Error Categories

Defined by `ErrorCategory` in `Sources/HirundoCore/Errors.swift`:

- `CONFIG`: Configuration issues
- `MARKDOWN`: Content processing
- `TEMPLATE`: Template rendering
- `BUILD`: Site generation
- `ASSET`: Asset processing
- `HOTRELOAD`: File watching
- `SERVER`: Development server
- `NETWORK`: Network operations
- `FILESYSTEM`: File operations

Category choice reflects the real cause rather than the throwing subsystem: for
example `ScaffoldError.invalidTitle` and `.emptyDestinationPath` are reported as
`CONFIG` (a usage mistake), while the remaining scaffold errors are `FILESYSTEM`.

## Dependencies

### Core Dependencies

- **swift-markdown**: Apple's CommonMark parser
- **Stencil**: Template engine
- **PathKit**: Path utilities (used directly by `TemplateEngine`)
- **Yams**: YAML parser
- **Swifter**: HTTP server
- **swift-argument-parser**: CLI interface

### Dependency Management

- Minimal dependency surface
- Version pinning for stability
- Security audit pipeline
- Regular updates

## Testing Strategy

### Test Types

1. **Unit Tests**: Individual component testing
2. **Integration Tests**: Component interaction
3. **Security Tests**: Vulnerability testing
4. **Performance Tests**: Benchmark validation
5. **End-to-End Tests**: Full workflow validation

### Test Coverage Targets

These are goals, not measured figures; coverage is not currently enforced in CI.

- Core functionality: >90%
- Security functions: 100%
- Error paths: >80%
- CLI interface: >85%

See `TESTING.md` for the current state of the suite, including known failures.

## Build System

### Swift Package Manager

- Clean package structure
- Platform-specific targets
- Conditional compilation
- Resource handling

### CI/CD Pipeline

`.github/workflows/ci.yml` runs on macOS only:

1. **Build and test**: `swift build` then `swift test`, across an Xcode 16.1 /
   16.2 matrix
2. **ThreadSanitizer**: `swift test --sanitize=thread`, `continue-on-error` so
   warnings from external libraries do not fail the run

`.github/workflows/release.yml` handles release artifacts. There is no
vulnerability-scanning or benchmarking job.

## Future Architecture

### Planned Improvements

- **Incremental Builds**: File-level change detection, backed by parsed-content
  and rendered-page caches
- **Distributed Caching**: Network cache sharing
- **Extensibility**: The plugin system was removed in favour of built-in
  features; any future extension mechanism (e.g. WebAssembly-sandboxed) would be
  a new design, not a revival of the old one
- **Performance Monitoring**: Built-in profiling
- **Advanced Security**: Code signing, sandboxing

### Scalability Considerations

- **Large Sites**: Streaming processing
- **Memory Usage**: Configurable limits
- **Build Times**: Parallel optimization
- **Cache Efficiency**: Intelligent strategies

This architecture ensures Hirundo remains fast, secure, and maintainable while providing a foundation for future enhancements.

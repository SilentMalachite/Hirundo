Project: Hirundo – a Swift 6 static site generator with a CLI (`hirundo`) and a core library (`HirundoCore`). Purpose: parse Markdown with front matter, render via Stencil templates, build site, and serve locally with live reload. Key features: secure parsing/validation, asset pipeline, plugin system (RSS, Sitemap, Minify), development server with live reload, config via YAML.

Tech stack: Swift 6 (SwiftPM), macOS 14+; Libraries: swift-markdown, Yams, Stencil, Swifter; Tests: XCTest.

Repo structure:
- Package.swift, Package.resolved
- Sources/Hirundo (CLI)
- Sources/HirundoCore (core: parsing, templates, server, plugins)
- Tests/HirundoTests (XCTest)
- test-site/, test-hirundo/ fixtures

Entrypoints:
- `swift run hirundo` (CLI), commands: init, build, serve, new(post/page), clean

Design notes: CLI delegates to `HirundoCore`; strong security focus (input/path validation, XSS protection); concurrency via actors/queues; plugin architecture with hooks (before/after build, content transform, assets).
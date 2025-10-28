
# Development Guide

This document summarizes common development tasks and local workflows for Hirundo.

## Environment

- Swift 6.0+
- macOS 12+
- Xcode 16+ recommended for macOS development

## Build, Test, Run

- Build (debug): `swift build`
- Build (release): `swift build -c release`
- Run CLI help: `swift run hirundo --help`
- Development server: `swift run hirundo serve`
- Build a site: `swift run hirundo build --clean`
- Run tests: `swift test`

Tip: set verbose logs when diagnosing issues

```bash
HIRUNDO_LOG_LEVEL=debug swift run hirundo build
```

## Working With the Fixture

A ready-to-use fixture is provided for end-to-end checks.

```bash
cd test-hirundo
swift run --package-path .. hirundo build --clean
swift run --package-path .. hirundo serve
# open http://localhost:8080 and edit files under test-hirundo/content/
```

## Repository Conventions

- Coding style: Swift API Design Guidelines; 4-space indent; ~120 col.
- Public API: add `///` doc comments with parameters/returns.
- Errors: prefer typed `Error` enums; propagate via `throws` and test both success and failure.
- Layout: organize files by feature (e.g., `Models/`, `Plugins/`, `Utilities/`).

## Commit and PR

- Use Conventional Commits, e.g. `feat: add RSS plugin option`, `fix: prevent path traversal`.
- Keep changes focused and documented.
- Before opening a PR:
  - Run `swift test` and ensure all tests pass.
  - Update docs (README/ARCHITECTURE/SECURITY/CHANGELOG) if behavior changes.
  - Note breaking changes explicitly.

See also: `CONTRIBUTING.md` for the full contribution flow.

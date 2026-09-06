# Contributing to Hirundo

Thank you for your interest in contributing to Hirundo! This document provides guidelines and information for contributors.

## Getting Started

### Prerequisites

- **Swift 6.0 or later** (required for concurrency features)
- macOS 12+
- Xcode 16+ (for macOS development)
- Git

### Development Setup

1. **Fork the repository**
   ```bash
   # Fork the repo on GitHub, then clone your fork
   git clone https://github.com/SilentMalachite/Hirundo.git
   cd hirundo
   ```

2. **Build the project**
   ```bash
   swift build
   ```

3. **Run tests**
   ```bash
   swift test
   ```

4. **Install for local development**
   ```bash
   swift build -c release
   cp .build/release/hirundo /usr/local/bin/hirundo-dev
   ```

## Development Workflow

### Branching Strategy

- `main` - Production-ready code
- `develop` - Integration branch for features
- `feature/description` - Feature branches
- `bugfix/description` - Bug fix branches
- `hotfix/description` - Critical fixes

### Making Changes

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow Swift coding conventions
   - Add tests for new functionality
   - Update documentation as needed

3. **Test your changes**
   ```bash
   # Run all tests
   swift test
   
   # Test with a real site
   cd test-site
   hirundo-dev build
   hirundo-dev serve
   ```

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   ```

5. **Push and create a pull request**
   ```bash
   git push origin feature/your-feature-name
   ```

## Code Style Guidelines

### Swift Style

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use 4 spaces for indentation
- Maximum line length: 120 characters
- Use meaningful variable and function names
- Add documentation comments for public APIs

### Example

```swift
/// Generates a static site from the given configuration
/// - Parameters:
///   - config: The site configuration
///   - clean: Whether to clean the output directory first
/// - Throws: `SiteGeneratorError` if generation fails
public func generateSite(config: SiteConfig, clean: Bool = false) throws {
    // Implementation
}
```

### File Organization

```
Sources/
├── Hirundo/                # CLI executable
│   ├── CommandMain.swift   # @main entry point, subcommand registration
│   ├── ErrorHandling.swift # Shared CLI error reporting
│   └── Commands/           # init, build, serve, new, clean
├── HirundoCore/            # Core library
│   ├── Models/             # Config and data models
│   ├── Parsers/            # Front matter and markdown parsing
│   ├── Processors/         # Markdown node processing
│   ├── Renderers/          # HTML rendering
│   ├── Sanitizers/         # HTML sanitization
│   ├── Scaffold/           # `hirundo init` site scaffolding
│   ├── Templates/          # Stencil cache, filters, context building
│   ├── Assets/             # Asset processing, fingerprinting, and reference rewriting
│   ├── Validators/         # Markdown validation
│   ├── Utils/, Utilities/  # Helper utilities
│   └── *.swift             # Core functionality
```

The CLI exposes five subcommands: `init`, `build`, `serve`, `new`
(`new post` / `new page`), and `clean`.

## Testing Guidelines

### Unit Tests

- Write tests for all public APIs
- Use descriptive test names: `testGeneratesSitemapWithCorrectURLs()`
- Test both success and failure cases
- Use `XCTAssert` family of functions

### Integration Tests

- Test command-line interface
- Test with real markdown files
- Test built-in features (`features:` toggles in `config.yaml`)
- Test development server

### Test Structure

```swift
import XCTest
@testable import HirundoCore

final class SiteGeneratorTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        tempDirectory = createTemporaryDirectory()
    }
    
    override func tearDown() {
        removeTemporaryDirectory(tempDirectory)
        super.tearDown()
    }
    
    func testGeneratesBasicSite() {
        // Test implementation
    }
}
```

## Commit Message Convention

We follow Conventional Commits. Examples:

- `feat: merge existing .gitignore on init`
- `fix: prevent path traversal`
- `docs: add DEVELOPMENT and TESTING guides`
- `refactor: simplify template cache keys`
- `test: cover scaffold error mapping edge cases`

Use imperative tone and scope when helpful, and reference issues when applicable, e.g. `Fixes #123`.

## Pre-PR Checklist

- `swift test` passes with no failures (see `TESTING.md`)
- Documentation updated as needed (README/ARCHITECTURE/SECURITY/CHANGELOG)
- Public APIs include `///` docs for new/changed symbols
- Breaking changes clearly called out in the PR description
- Changes are minimal, focused, and follow repository conventions

## Documentation

### Code Documentation

- Use Swift documentation comments (`///`)
- Document all public types and methods
- Include parameter descriptions and return values
- Add usage examples for complex APIs

### User Documentation

- Update README.md for new features
- Add examples to documentation
- Update command help text
- Consider adding to wiki for complex features

## Built-in Features

Hirundo has no plugin architecture. The plugin system was removed in Stage 2 and
replaced by compiled-in feature toggles; there is no `Plugin` protocol,
`PluginContext`, or dynamic loading, and no `plugins:` config block.

### Adding a Feature

1. Add a `Bool` to `Features` in `Sources/HirundoCore/Models/Features.swift`.
   All toggles default to `false`:

```swift
public struct Features: Codable, Sendable, Equatable {
    public var sitemap: Bool
    public var rss: Bool
    public var searchIndex: Bool
    public var minify: Bool
    public var fingerprint: Bool
}
```

2. Branch on it in `SiteGenerator`, alongside the existing feature generators:

```swift
if config.features.sitemap {
    try generateSitemap(outputURL: outputURL)
}
```

3. Add tests covering both the enabled and disabled paths
4. Document the new key in README and `ARCHITECTURE.md`

Users enable features under `features:` in `config.yaml`:

```yaml
features:
  sitemap: true
  rss: true
  searchIndex: false
  minify: true
  fingerprint: false
```

Note that `minify` enables CSS and JS asset minification together; it does not
minify HTML, and there is no separate per-language toggle.

### Guidelines

- Keep built-in features minimal and focused
- Ensure good test coverage
- Follow the existing feature-generator patterns in `SiteGenerator`

## Submitting Changes

### Pull Request Process

1. **Ensure your PR addresses an issue**
   - Reference the issue number in your PR description
   - Create an issue first if one doesn't exist

2. **Write a clear PR description**
   - Explain what changes you made and why
   - Include screenshots for UI changes
   - List any breaking changes

3. **Ensure tests pass**
   - All existing tests must continue to pass
   - Add new tests for your functionality
   - Maintain or improve code coverage

4. **Update documentation**
   - Update README.md if needed
   - Add inline code documentation
   - Update CHANGELOG.md

### PR Template

```markdown
## Description
Brief description of the changes.

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] All tests pass
- [ ] Added new tests
- [ ] Tested manually

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review of code completed
- [ ] Documentation updated
- [ ] No breaking changes (or breaking changes documented)
```

## Issue Reporting

### Bug Reports

Use the bug report template and include:
- Swift version
- Operating system
- Hirundo version
- Steps to reproduce
- Expected vs actual behavior
- Sample configuration/content if relevant

### Feature Requests

- Describe the problem you're trying to solve
- Explain the proposed solution
- Consider alternative solutions
- Discuss implementation complexity

## Release Process

### Versioning

We follow [Semantic Versioning](https://semver.org/):
- `MAJOR.MINOR.PATCH`
- Major: Breaking changes
- Minor: New features (backward compatible)
- Patch: Bug fixes

### Release Checklist

1. Update version numbers
2. Update CHANGELOG.md
3. Run full test suite
4. Create release tag
5. Update documentation
6. Announce release

## Community Guidelines

### Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Focus on constructive feedback
- Help others learn and grow

### Communication

- Use GitHub issues for bug reports and feature requests
- Use GitHub discussions for questions and general discussion
- Be patient and helpful in code reviews
- Provide context and examples in discussions

## Performance Considerations

### Build Performance

- Profile build times for large sites
- Consider memory usage for large numbers of files
- Benchmark changes that affect core generation

### Runtime Performance

- Monitor development server startup time
- Test live reload responsiveness
- Consider the cost of built-in features that walk the output tree (sitemap,
  search index)

## Security Considerations

- Validate all user inputs
- Prevent path traversal attacks
- Sanitize HTML output when needed
- Be careful with file system operations

## Getting Help

- Check existing issues and documentation first
- Use GitHub discussions for questions
- Provide minimal reproducible examples
- Be specific about your environment and steps

Thank you for contributing to Hirundo! 🦀

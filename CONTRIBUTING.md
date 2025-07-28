# Contributing to Hirundo

Thank you for your interest in contributing to Hirundo! This document provides guidelines and information for contributors.

## Getting Started

### Prerequisites

- Swift 5.9 or later
- macOS 13+ or Linux
- Xcode 15+ (for macOS development)
- Git

### Development Setup

1. **Fork the repository**
   ```bash
   # Fork the repo on GitHub, then clone your fork
   git clone https://github.com/SilentMalachite/hirundo.git
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
├── Hirundo/           # CLI executable
│   └── main.swift     # Command line interface
├── HirundoCore/       # Core library
│   ├── Models/        # Data models
│   ├── Plugins/       # Plugin system
│   ├── Utilities/     # Helper utilities
│   └── *.swift        # Core functionality
```

## Testing Guidelines

### Unit Tests

- Write tests for all public APIs
- Use descriptive test names: `testGeneratesSitemapWithCorrectURLs()`
- Test both success and failure cases
- Use `XCTAssert` family of functions

### Integration Tests

- Test command-line interface
- Test with real markdown files
- Test plugin functionality
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

## Plugin Development

### Creating a Plugin

1. Implement the `Plugin` protocol:

```swift
import HirundoCore

public struct MyPlugin: Plugin {
    public let name = "MyPlugin"
    public let version = "1.0.0"
    
    public func process(site: Site, context: PluginContext) throws -> Site {
        // Plugin implementation
        return site
    }
}
```

2. Add tests for your plugin
3. Update documentation
4. Consider making it a separate package

### Built-in Plugins

- Keep core plugins minimal and focused
- Ensure good test coverage
- Follow the existing plugin patterns

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
- Consider plugin performance impact

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
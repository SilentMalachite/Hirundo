# Hirundo Architecture

This document provides an overview of Hirundo's architecture, design principles, and implementation details.

## Overview

Hirundo is built with a modular, security-first architecture that prioritizes performance, maintainability, and extensibility.

```
┌─────────────────────────────────────────────────────────────┐
│                     Hirundo CLI                            │
│                   (ArgumentParser)                         │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                  HirundoCore                               │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │SiteGenerator│  │TemplateEng. │  │  DevelopmentServer  │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │MarkdownPars│  │AssetPipeline│  │   HotReloadManager  │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │PluginManger│  │  FSEvents   │  │     ErrorSystem     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Site Generator (`SiteGenerator.swift`)

The central orchestrator responsible for:
- Content discovery and parsing
- Template rendering
- Asset processing
- Output generation
- Plugin coordination

**Key Features:**
- Parallel content processing
- Intelligent caching
- Error recovery
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
- Fingerprinting support

**Security Measures:**
- Path traversal prevention
- Safe processing validation
- Symlink resolution
- Content verification

### 5. Development Server (`DevelopmentServer.swift`)

Live development server with WebSocket support:
- File system watching
- Live reload functionality
- Error reporting
- Memory management

**Features:**
- FSEvents on macOS, fallback on Linux
- WebSocket session cleanup
- Real-time error notifications
- Request logging

### 6. Plugin System (`PluginManager.swift`, `Plugin.swift`)

Extensible plugin architecture:
- Built-in plugin registration
- Dynamic loading (disabled for security)
- Lifecycle management
- Dependency resolution

**Built-in Plugins:**
- Sitemap generation
- RSS feed creation
- HTML minification
- Search index generation

## Security Architecture

### Input Validation Layer

```
User Input → Validation → Sanitization → Processing
     ↓           ↓            ↓           ↓
  - Size       - Path      - Content   - Safe
  - Format     - Type      - Escape    - Output
  - Content    - Perms     - Filter    - Monitor
```

### Path Security

1. **Sanitization**: Remove dangerous components (`..`, `~`, etc.)
2. **Validation**: Check against allowed patterns
3. **Resolution**: Resolve symlinks safely
4. **Verification**: Confirm final path is within bounds

### Memory Safety

- Automatic resource cleanup
- WebSocket session management
- File handle lifecycle
- Buffer size limits

## Performance Architecture

### Caching Strategy

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Parse Cache    │    │  Render Cache    │    │ Template Cache  │
│                 │    │                  │    │                 │
│ • Markdown AST  │    │ • Rendered HTML  │    │ • Compiled      │
│ • Frontmatter   │    │ • Processed CSS  │    │   Templates     │
│ • Metadata      │    │ • Optimized JS   │    │ • Filter Chain  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         ↑                       ↑                       ↑
         └───────────────────────┼───────────────────────┘
                                 ↓
                    ┌─────────────────────────┐
                    │   Intelligent           │
                    │   Invalidation          │
                    │                         │
                    │ • File change detection │
                    │ • Dependency tracking   │
                    │ • Incremental updates   │
                    └─────────────────────────┘
```

### Parallel Processing

- Concurrent content parsing
- Parallel asset processing
- Async I/O operations
- Worker pool management

## Configuration System

### Type-Safe Configuration

```swift
HirundoConfig
├── Site (required)
├── Build (optional, defaults)
├── Server (optional, defaults)
├── Blog (optional, defaults)
├── Limits (optional, defaults)
└── Plugins (optional, empty)
```

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

### Error Categories

- `CONFIG`: Configuration issues
- `MARKDOWN`: Content processing
- `TEMPLATE`: Template rendering
- `BUILD`: Site generation
- `ASSET`: Asset processing
- `PLUGIN`: Plugin system
- `HOTRELOAD`: File watching
- `SERVER`: Development server

## Dependencies

### Core Dependencies

- **swift-markdown**: Apple's CommonMark parser
- **Stencil**: Template engine
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

### Test Coverage

- Core functionality: >90%
- Security functions: 100%
- Error paths: >80%
- CLI interface: >85%

## Build System

### Swift Package Manager

- Clean package structure
- Platform-specific targets
- Conditional compilation
- Resource handling

### CI/CD Pipeline

1. **Build**: Multi-platform compilation
2. **Test**: Comprehensive test suite
3. **Security**: Vulnerability scanning
4. **Performance**: Benchmark validation
5. **Release**: Artifact generation

## Future Architecture

### Planned Improvements

- **Incremental Builds**: File-level change detection
- **Distributed Caching**: Network cache sharing
- **Advanced Plugins**: WebAssembly support
- **Performance Monitoring**: Built-in profiling
- **Advanced Security**: Code signing, sandboxing

### Scalability Considerations

- **Large Sites**: Streaming processing
- **Memory Usage**: Configurable limits
- **Build Times**: Parallel optimization
- **Cache Efficiency**: Intelligent strategies

This architecture ensures Hirundo remains fast, secure, and maintainable while providing a foundation for future enhancements.
# Hirundo 🦅

A modern, fast, and secure static site generator built with Swift.

[![Swift Version](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2012%2B-blue.svg)](https://github.com/SilentMalachite/Hirundo)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Build](https://img.shields.io/badge/Build-See_CI-blue.svg)](https://github.com/SilentMalachite/Hirundo/actions)
[![Security](https://img.shields.io/badge/Security-Policy_Available-lightgrey.svg)](SECURITY.md)
[![Release](https://img.shields.io/github/v/release/SilentMalachite/Hirundo)](https://github.com/SilentMalachite/Hirundo/releases)
[![Tests](https://img.shields.io/badge/Tests-Passing-green.svg)](#testing)

## Features

- **🚀 Blazing Fast**: Built with Swift for optimal performance with multi-level caching
- **📝 Markdown**: Full CommonMark support with frontmatter using Apple's swift-markdown
- **🎨 Templates**: Powerful Stencil-based templating engine with custom filters
- **🔄 Live Reload**: Development server with automatic rebuilding and real-time error reporting
- **🧩 Built-in Features**: Useful capabilities like sitemap/RSS/search/minify are available out of the box
- **💾 Smart Caching**: Multi-level intelligent caching for lightning-fast rebuilds
- **📦 Type Safe**: Strongly typed configuration and models with comprehensive validation
- **⚡ Simple**: Clean, easy-to-use configuration without unnecessary complexity
- **🛡️ Memory Safe**: Advanced memory management for WebSocket connections and file watching

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Frontmatter](#frontmatter)
- [Templates](#templates)
- [Development](#development)
- [Testing](#testing)
- [License](#license)

## Quick Start

### Installation

#### Using Swift Package Manager

```bash
git clone https://github.com/SilentMalachite/Hirundo.git
cd hirundo
swift build -c release
cp .build/release/hirundo /usr/local/bin/
```

#### From Source

```bash
swift build -c release
```

### Create Your First Site

```bash
# Create a new site
hirundo init my-site --blog

# Navigate to your site
cd my-site

# Start the development server
hirundo serve
```

Your site will be available at `http://localhost:8080` with live reload enabled.

## Commands

### `hirundo init`
Create a new Hirundo site.

```bash
hirundo init [path] [options]

Options:
  --title <title>     Site title (default: "My Hirundo Site")
  --blog             Include blog functionality
  --force            Force creation in non-empty directory
```

### `hirundo build`
Build your static site.

```bash
hirundo build [options]

Options:
  --config <file>     Configuration file path (default: config.yaml)
  --environment <env> Build environment (default: production)
  --drafts           Include draft posts
  --clean            Clean output before building
```

### `hirundo serve`
Start the development server with live reload.

```bash
hirundo serve [options]

Options:
  --port <port>      Server port (default: 8080)
  --host <host>      Server host (default: localhost)
  --no-reload        Disable live reload
  --no-browser       Don't open browser automatically
```

### `hirundo new`
Create new content.

```bash
# Create a new blog post
hirundo new post "My Post Title" --tags "swift,web" --categories "development"

# Create a new page
hirundo new page "About Us" --layout "default"
```

### `hirundo clean`
Clean output directory and caches.

```bash
hirundo clean [options]

Options:
  --cache    Also clean asset cache
  --force    Skip confirmation
```

## Project Structure

```
my-site/
├── config.yaml          # Site configuration
├── content/              # Markdown content
│   ├── index.md         # Home page
│   ├── about.md         # About page
│   └── posts/           # Blog posts
├── templates/            # HTML templates
│   ├── base.html        # Base layout
│   ├── default.html     # Default page template
│   └── post.html        # Blog post template
├── static/              # Static assets
│   ├── css/            # Stylesheets
│   ├── js/             # JavaScript
│   └── images/         # Images
└── _site/              # Generated output (git ignored)
```

## Configuration

### Site Configuration (`config.yaml`)

```yaml
site:
  title: "My Site"
  description: "A site built with Hirundo"
  url: "https://example.com"
  language: "en-US"
  author:
    name: "Your Name"
    email: "your.email@example.com"

build:
  contentDirectory: "content"
  outputDirectory: "_site"
  staticDirectory: "static"
  templatesDirectory: "templates"

server:
  port: 8080
  liveReload: true

blog:
  postsPerPage: 10
  generateArchive: true
  generateCategories: true
  generateTags: true
  rssEnabled: true

# Performance limits (optional)
limits:
  maxMarkdownFileSize: 10485760     # 10MB
  maxConfigFileSize: 1048576        # 1MB
  maxFrontMatterSize: 100000        # 100KB
  maxFilenameLength: 255
  maxTitleLength: 200
  maxDescriptionLength: 500

# Features (optional)
features:
  sitemap: true
  rss: true
  searchIndex: true
  minify: true


```

## Frontmatter

Hirundo supports YAML frontmatter in your Markdown files:

```markdown
---
title: "My Post Title"
date: 2024-01-15T10:00:00Z
layout: "post"
categories: ["development", "swift"]
tags: ["static-site", "web"]
draft: false
---

# My Post Title

Your content here...
```

## Templates

Hirundo uses the [Stencil](https://github.com/stencilproject/Stencil) templating engine. Templates have access to these variables:

- `site`: Site configuration and metadata
- `page`: Current page data
- `pages`: All pages
- `posts`: All blog posts
- `categories`: Category mappings
- `tags`: Tag mappings
- `content`: Rendered page content

### Custom Filters

- `date`: Format dates
- `slugify`: Create URL slugs
- `excerpt`: Extract excerpts
- `absolute_url`: Create absolute URLs
- `markdown`: Render Markdown

### Example Template

```html
{% extends "base.html" %}

{% block content %}
<article>
    <h1>{{ page.title }}</h1>
    {% if page.date %}
    <time>{{ page.date | date: "%B %d, %Y" }}</time>
    {% endif %}
    {{ content }}
</article>
{% endblock %}
```

## Features

Hirundo provides built-in features. Dynamic loading of external code is not supported for security and simplicity.

### Sitemap
Generates `sitemap.xml` for search engines.

### RSS
Creates `rss.xml` for your blog posts.

### Minify
Minifies CSS/JS assets for better performance.

### Search Index
Generates a search index for client-side search functionality.

## Security Features

Hirundo implements appropriate security measures for a static site generator:

### Input Validation
- **File Size Limits**: Configurable limits for markdown files and frontmatter
- **Path Validation**: Standard path traversal protection
- **Content Processing**: Safe processing of user-generated content

### Asset Processing
- **CSS/JS Processing**: Standard processing with minification support
- **Path Sanitization**: Basic path cleaning and validation

### Development Server
- **WebSocket Management**: Clean WebSocket connection handling
- **Live Reload**: Simple file watching with automatic cleanup
- **Error Handling**: Secure error reporting

### Local Verification with Fixture
You can quickly verify end-to-end using the provided fixture:

```bash
cd test-hirundo
swift run --package-path .. hirundo build --clean
swift run --package-path .. hirundo serve
# open http://localhost:8080 and edit files under test-hirundo/content/
```

## Development

### Requirements

- Swift 6.0+
- macOS 12+
- Xcode 16+ (for macOS development)

### Building from Source

```bash
git clone https://github.com/SilentMalachite/Hirundo.git
cd hirundo
swift build
```

### Running Tests

```bash
swift test
```

## Documentation

- Development Guide: see `DEVELOPMENT.md`
- Testing Guide: see `TESTING.md`
- Architecture: see `ARCHITECTURE.md`
- Security Policy and guidance: see `SECURITY.md` and `WEBSOCKET_AUTHENTICATION.md`
- Contributing Guide: see `CONTRIBUTING.md`
- 日本語ドキュメント: `README.ja.md`

## Testing

Hirundo includes a test suite that covers core functionality:

- **Unit Tests**: Individual component testing
- **Integration Tests**: End-to-end workflow validation
- **Edge Case Tests**: Error handling and edge case scenarios

### Test Categories

- `AssetPipelineTests` - Asset processing and minification
- `ConfigTests` - Configuration validation and parsing
- `ContentProcessorTests` - Markdown processing and validation
- `EdgeCaseTests` - Error handling and edge case scenarios
- `IntegrationTests` - End-to-end functionality
- `HotReloadManagerTests` - File watching functionality

All tests are expected to pass. Run `swift test` to verify on your environment.

### Debug Mode

Set the log level for detailed output:

```bash
HIRUNDO_LOG_LEVEL=debug hirundo build
```

## Technical Architecture

### Dependencies

- **[swift-markdown](https://github.com/apple/swift-markdown)**: Apple's CommonMark parser
- **[Stencil](https://github.com/stencilproject/Stencil)**: Template engine
- **[Yams](https://github.com/jpsim/Yams)**: YAML parser
- **[Swifter](https://github.com/httpswift/swifter)**: Lightweight HTTP server
- **[swift-argument-parser](https://github.com/apple/swift-argument-parser)**: Command-line interface

### Performance Features

- **Multi-level Caching**: Parsed content, rendered pages, and template caching
- **Async/Await**: Parallel processing for improved build times
- **Streaming**: Efficient memory usage for large sites
- **Memory Management**: Clean resource management and file handle handling
- **Hot Reload**: File system monitoring with automatic cleanup

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## License

Hirundo is released under the MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with [Swift](https://swift.org)
- Inspired by modern static site generators
- Uses Apple's [swift-markdown](https://github.com/apple/swift-markdown) for reliable Markdown parsing

---

Made with ❤️ and Swift

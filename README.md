# Hirundo 🦅

A modern, fast, and secure static site generator built with Swift.

[![Swift Version](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B-blue.svg)](https://github.com/SilentMalachite/hirundo)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](https://github.com/SilentMalachite/hirundo/actions)

## Features

- **🚀 Blazing Fast**: Built with Swift for optimal performance with multi-level caching
- **🔒 Secure**: Comprehensive input validation, path traversal protection, and safe asset processing  
- **📝 Markdown**: Full CommonMark support with frontmatter using Apple's swift-markdown
- **🎨 Templates**: Powerful Stencil-based templating engine with custom filters
- **🔄 Live Reload**: Development server with automatic rebuilding and real-time error reporting
- **🧩 Extensible**: Plugin architecture for custom functionality with built-in plugins
- **💾 Smart Caching**: Multi-level intelligent caching for lightning-fast rebuilds
- **📦 Type Safe**: Strongly typed configuration and models with comprehensive validation
- **⚡ Configurable**: Customizable security limits and performance settings
- **🛡️ Memory Safe**: Advanced memory management for WebSocket connections and file watching
- **⏱️ Timeout Protection**: Configurable timeouts for all I/O operations to prevent DoS attacks
- **🌐 CORS Ready**: Configurable Cross-Origin Resource Sharing support for development

## Quick Start

### Installation

#### Using Swift Package Manager

```bash
git clone https://github.com/SilentMalachite/hirundo.git
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
  cors:
    enabled: true
    allowedOrigins: ["http://localhost:*", "https://localhost:*"]
    allowedMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allowedHeaders: ["Content-Type", "Authorization"]
    maxAge: 3600
    allowCredentials: false

blog:
  postsPerPage: 10
  generateArchive: true
  generateCategories: true
  generateTags: true
  rssEnabled: true

# Security and performance limits (optional)
limits:
  maxMarkdownFileSize: 10485760     # 10MB
  maxConfigFileSize: 1048576        # 1MB
  maxFrontMatterSize: 100000        # 100KB
  maxFilenameLength: 255
  maxTitleLength: 200
  maxDescriptionLength: 500

# Plugin configuration (optional)
plugins:
  - name: "sitemap"
    enabled: true
  - name: "rss"
    enabled: true
  - name: "minify"
    enabled: true
    settings:
      minifyHTML: true
      minifyCSS: true
      minifyJS: false  # Disabled for safety

# Timeout configuration (optional)
timeouts:
  fileReadTimeout: 30.0              # File read operations (seconds)
  fileWriteTimeout: 30.0             # File write operations (seconds)
  directoryOperationTimeout: 15.0    # Directory operations (seconds)
  httpRequestTimeout: 10.0           # HTTP requests (seconds)
  fsEventsTimeout: 5.0              # File system events startup (seconds)
  serverStartTimeout: 30.0          # Server startup (seconds)
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

## Plugins

Hirundo includes several built-in plugins:

### Sitemap Plugin
Generates `sitemap.xml` for search engines.

### RSS Plugin
Creates RSS feeds for your blog posts.

### Minify Plugin
Minifies HTML output for better performance.

### Search Index Plugin
Generates a search index for client-side search functionality.

## Security Features

Hirundo prioritizes security with comprehensive protection measures:

### Input Validation
- **File Size Limits**: Configurable limits for markdown files, config files, and frontmatter
- **Path Validation**: Advanced path traversal protection with symlink resolution
- **Content Sanitization**: Safe processing of user-generated content

### Asset Processing Security
- **Safe CSS/JS Processing**: Validation before minification to prevent code injection
- **Disabled JS Transpilation**: Potentially unsafe regex-based transpilation is disabled by default
- **Path Sanitization**: Comprehensive path cleaning with security checks

### Development Server Security
- **WebSocket Protection**: Memory-safe WebSocket session management with authentication
- **CORS Configuration**: Flexible Cross-Origin Resource Sharing controls
- **Timeout Protection**: Configurable timeouts for all I/O operations to prevent DoS attacks
- **Error Isolation**: Secure error reporting without information leakage
- **File Watching**: Safe file system monitoring with cleanup

## Development

### Requirements

- Swift 6.0+
- macOS 14+
- Xcode 16+ (for macOS development)

### Building from Source

```bash
git clone https://github.com/SilentMalachite/hirundo.git
cd hirundo
swift build
```

### Running Tests

```bash
swift test
```

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

- **Multi-level Caching**: Parsed content, rendered pages, and template caching with intelligent invalidation
- **Async/Await**: Parallel processing for improved build times
- **Streaming**: Efficient memory usage for large sites with controlled resource usage
- **Memory Management**: Advanced WebSocket session cleanup and file handle management
- **Configurable Limits**: Tunable performance and security limits
- **Hot Reload**: Fast file system monitoring with FSEvents on macOS and fallback on Linux
- **Timeout Management**: Comprehensive timeout controls for all operations (0.1s to 600s range)
- **Resource Protection**: CPU time and memory limits to prevent resource exhaustion

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
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

- **🚀 Fast**: Built with Swift, with caching for parsed content, rendered pages, and templates
- **📝 Markdown**: CommonMark support with YAML frontmatter using Apple's swift-markdown
- **🎨 Templates**: Stencil-based templating engine with 20 custom filters
- **🔄 Live Reload**: Development server that rebuilds on change and pushes reloads over WebSocket
- **🧩 Built-in Features**: Sitemap, RSS, search index, and asset minification as simple on/off flags
- **📦 Type Safe**: Strongly typed, validated configuration and models
- **⚡ Simple**: A small configuration surface — six top-level keys, no plugin runtime to manage

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Frontmatter](#frontmatter)
- [Templates](#templates)
- [Built-in Features](#built-in-features)
- [Not Yet Implemented](#not-yet-implemented)
- [Security](#security)
- [Development](#development)
- [Testing](#testing)
- [License](#license)

## Quick Start

### Installation

```bash
git clone https://github.com/SilentMalachite/Hirundo.git
cd Hirundo
swift build -c release
cp .build/release/hirundo /usr/local/bin/
```

### Create Your First Site

```bash
# Create a new site
hirundo init my-site --blog

# Navigate to your site
cd my-site

# Build it
hirundo build

# Start the development server
hirundo serve
```

Your site will be available at `http://localhost:8080` with live reload enabled.

> `hirundo serve` serves whatever is already in the output directory. Run `hirundo build`
> at least once before the first `serve`, otherwise every request returns 404 because
> there is nothing to serve yet.

## Commands

Every command also accepts `--verbose`, which prints the underlying error instead of
just the friendly summary.

### `hirundo init`
Create a new Hirundo site.

```bash
hirundo init [path] [options]

Arguments:
  path                Path where the new site will be created (default: ".")

Options:
  --title <title>     Site title (default: "My Hirundo Site")
  --blog              Include blog functionality
  --force             Allow scaffolding into a non-empty directory
  --verbose           Show verbose error information
```

Behaviour worth knowing:

- An **empty path argument is rejected**. Pass a directory path, or `.` for the current
  directory.
- An existing `.gitignore` is **merged, not overwritten** — including under `--force`.
  Merged files are reported as `📝 Updated <path>`, newly written ones as `✅ Created <path>`.
- A directory containing only `.git`, `.gitignore`, `.DS_Store`, `.svn`, or `.hg` still
  counts as empty, so you can initialise into a freshly cloned repository without `--force`.
- If scaffolding fails partway through, directories that this run created are **rolled back**
  rather than left behind half-populated.
- With `--blog`, the sample post is dated at generation time.

Files written by `hirundo init --blog`:

```
.gitignore
config.yaml
content/index.md
content/about.md
content/posts/hello-world.md   # --blog only
static/css/style.css
templates/base.html
templates/default.html
templates/post.html            # --blog only
```

Without `--blog`, `features.rss` and `blog.generateArchive` / `generateCategories` /
`generateTags` are all written as `false`.

### `hirundo build`
Build your static site.

```bash
hirundo build [options]

Options:
  --config <file>       Configuration file path (default: config.yaml)
  --environment <env>   Build environment, development/production (default: production)
  --drafts              Include draft posts
  --clean               Clean output before building
  --continue-on-error   Continue building even if some files fail (error recovery mode)
  --verbose             Show verbose error information
```

If the configuration file does not exist, the build falls back to project defaults rather
than failing. `--environment` is currently recorded and printed but does not change the
output; it is reserved for future conditional behaviour.

### `hirundo serve`
Start the development server with live reload.

```bash
hirundo serve [options]

Options:
  --port <port>      Server port (default: 8080)
  --host <host>      Server host (default: localhost)
  --no-reload        Disable live reload
  --no-browser       Don't open browser automatically
  --verbose          Show verbose error information
```

The server reads `config.yaml` from the current directory to find the output directory,
then serves files out of it:

- Directory requests resolve to that directory's `index.html`, so `/`, `/about`, and
  `/about/` all work.
- Requests that would climb out of the output directory (`/../../etc/passwd`) are rejected.
- With live reload on, a WebSocket endpoint is exposed at `/livereload`.

`--port` and `--host` are command-line only — `server.port` in `config.yaml` is not
consulted by `serve`.

### `hirundo new`
Create new content.

```bash
hirundo new post <title> [--slug <slug>] [--categories <list>] [--tags <list>]
                         [--template <template>] [--draft] [--open] [--verbose]
hirundo new page <title> [--path <path>] [--template <template>] [--open] [--verbose]
```

**`hirundo new post`**

| Option | Meaning |
|---|---|
| `--slug` | File name without the `.md` extension, used verbatim. Defaults to a slug derived from the title. |
| `--categories` | Comma-separated. Blank entries and duplicates are dropped. |
| `--tags` | Comma-separated. Blank entries and duplicates are dropped. |
| `--template` | Value for the `template:` key. Defaults to `post.html`. |
| `--draft` | Writes `draft: true`, so the file is skipped unless you build with `--drafts`. |
| `--open` | Opens the new file in `$VISUAL`, else `$EDITOR`. |

Creates `<contentDirectory>/posts/<slug>.md`:

```markdown
---
title: "My First Post"
date: 2026-09-05T12:00:00Z
categories: ["swift"]
tags: ["static-site"]
template: "post.html"
---

# My First Post

```

`categories`, `tags`, and `draft` appear only when you ask for them.

**`hirundo new page`**

| Option | Meaning |
|---|---|
| `--path` | Path relative to the content directory. `--path about/team` creates `content/about/team.md`, intermediate directories included. Defaults to a slug derived from the title. |
| `--template` | Value for the `template:` key. Defaults to `default.html`. |
| `--open` | Opens the new file in `$VISUAL`, else `$EDITOR`. |

Creates `<contentDirectory>/<path>.md`, with no `date:` key — the same shape as the
starter pages `hirundo init` writes.

**Notes**

- The content directory comes from `build.contentDirectory` in `config.yaml`. If there is
  no config file, or it exists but cannot be read, `content` is used and a warning is
  printed on stderr saying which of the two happened; the file is still created and the
  exit code stays 0. A missing config usually means you are not in a site root — the file
  is written, but nothing there will build until a `config.yaml` exists.
- **Neither command overwrites an existing file.** A collision is an error; pass a
  different `--slug` or `--path`, or edit the file that is already there.
- `--slug` decides the **file name only**. No `slug:` key is written into the frontmatter:
  the output URL comes from the file name while RSS links come from the post's slug, so a
  `slug:` that disagreed with the file name would make the two point at different URLs.
  A `--slug` you pass is used **verbatim** — it is not slugified — so it becomes the file
  name and therefore the URL segment exactly as typed, spaces and non-ASCII included.
  Only `/`, `\`, `.`, `..`, control characters and over-long values are rejected.
- `--open` only runs editors on an allow-list (`vim`, `nvim`, `nano`, `emacs`, `code`,
  `subl`, `vi`, `open`, and similar) and never goes through a shell. The name is run on
  its own, so a value carrying arguments (`code --wait`, `vim +startinsert`) is refused,
  as is an absolute path outside a small fixed list.
  If `$EDITOR` is unset, refused, or fails to start, the command prints a warning and
  still exits 0 — the file has already been written. The warning distinguishes "nothing
  set" from "set but refused", and names the refused value.

### `hirundo clean`
Clean output directory and caches.

```bash
hirundo clean [options]

Options:
  --cache    Also clean the .hirundo-cache directory
  --force    Actually delete (without this, the command only reports what it would delete)
  --verbose  Show verbose error information
```

> `clean` is a **dry run by default**. There is no interactive confirmation prompt:
> without `--force` it just lists the paths it would remove. The output directory is read
> from `build.outputDirectory` in `config.yaml`, falling back to `_site`.

## Project Structure

```
my-site/
├── config.yaml           # Site configuration
├── content/              # Markdown content
│   ├── index.md          # Home page
│   ├── about.md          # About page
│   └── posts/            # Blog posts
├── templates/            # Stencil templates
│   ├── base.html         # Base layout
│   ├── default.html      # Default page template
│   └── post.html         # Blog post template
├── static/               # Static assets, copied to the output root
│   └── css/
└── _site/                # Generated output (git ignored)
```

Anything under `static/` is copied to the **root** of the output directory — `static/css/style.css`
is served at `/css/style.css`, not `/static/css/style.css`. `hirundo init` creates only
`static/css/`; add `js/`, `images/`, or anything else as you need them.

## Configuration

`config.yaml` has exactly six top-level keys: `site`, `build`, `server`, `blog`, `features`,
and `limits`. Only `site` is required; every other block falls back to its defaults.

> ⚠️ **Unknown top-level keys are silently ignored.** A misspelled block (`serverr:`) or a
> block that does not exist (`timeouts:`, `plugins:`) is not an error — it simply has no
> effect. Check spelling against the list above if a setting seems not to apply.

```yaml
site:
  title: "My Site"                  # required
  url: "https://example.com"        # required
  description: "A site built with Hirundo"   # optional, max 500 chars
  language: "en-US"                 # optional, default "en-US"
  author:                           # optional
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
  postsPerPage: 10                  # 1-100
  generateArchive: true
  generateCategories: true
  generateTags: true

# Built-in feature flags. A mapping, not a list. Omit the block and all four are false.
features:
  sitemap: true
  rss: true
  searchIndex: true
  minify: true

# Security and performance limits. All ten keys are required if this block is present.
# The values below are the defaults.
limits:
  maxMarkdownFileSize: 10485760     # 10MB
  maxConfigFileSize: 1048576        # 1MB
  maxFrontMatterSize: 100000        # 100KB
  maxFilenameLength: 255
  maxTitleLength: 200
  maxDescriptionLength: 500
  maxUrlLength: 2000
  maxAuthorNameLength: 100
  maxEmailLength: 254
  maxLanguageCodeLength: 10
```

A minimal configuration is just the two required fields:

```yaml
site:
  title: "My Site"
  url: "https://example.com"
```

### Gotchas

- **`limits` is all-or-nothing.** Unlike every other block, it has no per-key defaults when
  decoding. If you include a `limits:` block you must list **all ten** keys — omitting even
  one fails the build with `Failed to parse configuration: The data couldn't be read because
  it is missing.` If you only want the defaults, omit the block entirely.
- **`features` is a mapping, not a list.** The legacy plugin form is no longer accepted and
  is a hard parse error:
  ```yaml
  # ✗ No longer parses
  features:
    - name: "sitemap"
      enabled: true
  ```
- **There is no `blog.rssEnabled`.** RSS is `features.rss`.
- **`server` supports only `port` and `liveReload`.** See [Not Yet Implemented](#not-yet-implemented).

### Defaults when a block is omitted

| Block | Behaviour when absent |
|-------|-----------------------|
| `build` | `content` / `_site` / `static` / `templates` |
| `server` | `port: 8080`, `liveReload: true` |
| `blog` | `postsPerPage: 10`, all `generate*` true |
| `features` | all four false |
| `limits` | the values shown in the example above |

`hirundo init` writes everything through `features` and omits `limits`, which therefore
runs on the defaults.

## Frontmatter

Hirundo reads YAML frontmatter from your Markdown files:

```markdown
---
title: "My Post Title"
date: 2024-01-15T10:00:00Z
description: "A short summary"
categories: ["development", "swift"]
tags: ["static-site", "web"]
draft: false
slug: "my-post-title"
template: "post.html"
---

# My Post Title

Your content here...
```

Recognised keys: `title`, `date`, `description`, `categories`, `tags`, `draft`, `slug`,
`template`, `type`, `author`.

- `draft: true` excludes the file unless you build with `--drafts`.
- `template:` selects the Stencil template. It must name a template that exists, or the
  build fails.
- **`layout:` is not read.** Use `template:` to override the template, or rely on the
  default (`post.html` for posts, `default.html` for pages). The starter content generated
  by `hirundo init` writes an explicit `template:` key.

## Templates

Hirundo uses the [Stencil](https://github.com/stencilproject/Stencil) templating engine.
Templates have access to these variables:

- `site`: Site configuration and metadata
- `page`: Current page data
- `pages`: All pages
- `posts`: All blog posts
- `categories`: Category mappings
- `tags`: Tag mappings
- `content`: Rendered page content

### Custom Filters

| Filter | Purpose |
|--------|---------|
| `date` | Format dates |
| `slugify` | Create URL slugs |
| `excerpt` | Extract excerpts |
| `markdown` | Render Markdown |
| `absolute_url` | Create absolute URLs |
| `relative_url` | Create root-relative URLs |
| `site_url` | Site URL from configuration |
| `site_title` | Site title from configuration |
| `site_description` | Site description from configuration |
| `join` | Join a list into a string |
| `length` | Length of a list or string |
| `first` | First element |
| `last` | Last element |
| `slice` | Sub-range of a list |
| `truncate` | Truncate a string |
| `strip` | Trim whitespace |
| `replace` | Substring replacement |
| `split` | Split a string into a list |
| `number` | Numeric formatting |
| `default` | Fallback for an empty value |

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

## Built-in Features

Hirundo ships four built-in features, toggled by the `features` block. Dynamic loading of
external code is not supported, for security and simplicity.

| Flag | Effect |
|------|--------|
| `sitemap` | Writes `sitemap.xml` to the output root |
| `rss` | Writes `rss.xml` from your posts |
| `searchIndex` | Writes `search-index.json` for client-side search |
| `minify` | Enables CSS and JS minification in the asset pipeline |

Note that `minify` applies to **CSS and JS assets only** — generated HTML is not minified.

Archive, category, and tag pages are controlled separately, by the `blog` block.

## Not Yet Implemented

These are documented here because earlier versions of this README described them as working.
They are not:

- **CORS configuration.** There is no `server.cors` block. `server` accepts only `port` and
  `liveReload`; a `cors:` key under it is silently ignored.
- **Timeout configuration.** There is no `timeouts` block and no configurable timeouts for
  file, directory, HTTP, file-watching, or server-start operations.
- **Plugin architecture.** The plugin system was removed; the four flags under `features`
  replace it. There is no custom-plugin development support, and no `imageOptimization` or
  `syntaxHighlight` feature.
- **WebSocket authentication for live reload.** There is no `/auth-token` endpoint and no
  token handshake; `/livereload` accepts connections directly. Do not expose the development
  server to an untrusted network.
- **Asset fingerprinting, source maps, and JS/CSS concatenation.** `build.enableAssetFingerprinting`,
  `enableSourceMaps`, `concatenateJS`, and `concatenateCSS` are accepted by the config parser
  but are not acted on anywhere.
- **`layout:` in frontmatter.** Use `template:`.

## Security

Hirundo implements security measures appropriate to a static site generator:

- **Input validation**: configurable size limits for Markdown files, the config file, and
  frontmatter; length limits on titles, descriptions, URLs, author names, e-mail addresses,
  and language codes.
- **Path validation**: `build` directories may not be absolute or contain `..`; the
  development server rejects request paths that escape the output directory.
- **Asset processing**: CSS/JS processing with optional minification.
- **Development server**: WebSocket session cleanup and file-watcher teardown on shutdown.

See [SECURITY.md](SECURITY.md) for the security policy.

### Local Verification with Fixture

You can verify end-to-end using the provided fixture:

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
cd Hirundo
swift build
```

### Debug Mode

Set the log level for detailed output:

```bash
HIRUNDO_LOG_LEVEL=debug hirundo build
```

## Testing

```bash
# Run all tests
swift test

# Run a specific suite
swift test --filter SiteGeneratorTests
swift test --filter ConfigTests
swift test --filter IntegrationTests

# Generate test coverage
swift test --enable-code-coverage
```

### Test Suites

- `AssetPipelineTests` — asset processing and minification
- `ConfigTests`, `ConfigParseTests` — configuration validation and parsing
- `MarkdownParserTests`, `SimpleMarkdownTest` — Markdown and frontmatter processing
- `TemplateEngineTests` — template rendering and filters
- `SiteGeneratorTests` — end-to-end site generation
- `SiteScaffolderTests`, `InitDestinationResolverTests`, `ScaffoldErrorMappingTests` — `hirundo init`
- `DevelopmentServerTests` — request routing and path containment
- `HotReloadManagerTests`, `HotReloadIntegrationTest`, `FSEventsMemoryTests` — file watching
- `ErrorRecoveryTests` — `--continue-on-error` behaviour
- `SecurityTests` — validation and path-traversal checks
- `IntegrationTests` — end-to-end workflows
- `DependencyCompatibilityTests`, `EditorCommandValidationTests`

## Documentation

- Development Guide: [`DEVELOPMENT.md`](DEVELOPMENT.md)
- Testing Guide: [`TESTING.md`](TESTING.md)
- Architecture: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- Security Policy: [`SECURITY.md`](SECURITY.md)
- Contributing Guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- 日本語ドキュメント: [`README.ja.md`](README.ja.md)

## Technical Architecture

### Dependencies

- **[swift-markdown](https://github.com/apple/swift-markdown)**: Apple's CommonMark parser
- **[Stencil](https://github.com/stencilproject/Stencil)**: Template engine
- **[Yams](https://github.com/jpsim/Yams)**: YAML parser
- **[Swifter](https://github.com/httpswift/swifter)**: Lightweight HTTP server
- **[PathKit](https://github.com/kylef/PathKit)**: Path utilities
- **[swift-argument-parser](https://github.com/apple/swift-argument-parser)**: Command-line interface

### Performance

- **Caching**: parsed content, rendered pages, and templates
- **Async/Await**: parallel processing for improved build times
- **Hot Reload**: FSEvents-based file system monitoring with cleanup on shutdown

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

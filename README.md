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
- **🧩 Built-in Features**: Sitemap, RSS, search index, asset minification, and asset fingerprinting as simple on/off flags
- **📦 Type Safe**: Strongly typed, validated configuration and models
- **⚡ Simple**: A small configuration surface — seven top-level keys, no plugin runtime to manage

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

Your site will be available at `http://127.0.0.1:8080` — the address `serve` prints and opens —
with live reload enabled.

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

The content directory is walked through symlinks. If `content/posts` is a link to a
directory elsewhere, the Markdown behind it is built, and each page keeps the URL its path
under `content/` implies — `content/posts/hello.md` publishes at `/posts/hello/` wherever
the file actually lives. A link is followed only while it stays inside the project
directory (the one holding `config.yaml`), so the build reads Markdown from inside the
project only: a link to anywhere else on the machine, or to the project directory itself
(`content/up -> ..`), is skipped, as is one pointing into the output, `static` or
`templates` directory. The same rule applies to a link naming a single file:
`content/notes.md -> ../shared/notes.md` is built, `content/leak.md ->
/Users/someone/private-notes.md` is skipped. A directory is entered once per build, so
links pointing at each other, or back at somewhere already walked, terminate instead of
being followed forever.
Every decision is printed as the build makes it — `Following content symlink:
content/posts -> ../shared-posts`.

### `hirundo serve`
Start the development server with live reload.

```bash
hirundo serve [options]

Options:
  --port <port>      Server port (defaults to server.port in config.yaml)
  --host <host>      Numeric address to bind to (default: localhost)
  --no-reload        Disable live reload
  --no-browser       Don't open browser automatically
  --drafts           Include draft posts
  --verbose          Show verbose error information
```

`serve` reads `config.yaml` from the current directory, builds the site once, then starts
serving while watching for changes. For both the port and live reload, the precedence is
CLI flag > `server` block in `config.yaml` > built-in default (port 8080, live reload on):
an explicit `--port` overrides `server.port`, and `--no-reload` always disables live reload
no matter what `server.liveReload` says; omit both and `config.yaml` decides. Whichever source
supplies it, the port must be between 1 and 65535.

`--host` is the address the server actually binds to, and accepts only a numeric address or
the literal `localhost` — any other host name is rejected. The default, `localhost`,
resolves to the IPv4 loopback address, so only this machine can connect. Pass
`--host 0.0.0.0` to accept connections from other machines; anyone who can then reach this
machine can read the site, so only do this on a trusted network. Open the site by IP
address when you do — a host name is refused by the live-reload check described below.

- Directory requests resolve to that directory's `index.html`, so `/`, `/about`, and
  `/about/` all work.
- Requests that would climb out of the output directory (`/../../etc/passwd`) are rejected.
- With live reload on, `serve` watches the content, templates and static directories (not
  the output directory) and rebuilds on change, then pushes a reload to every connected
  browser over a WebSocket exposed at `/livereload`.
- The `/livereload` handshake is screened before the connection is upgraded. It is accepted
  only when the request carries an `Origin` header whose host and port match the `Host` it
  was addressed to, and only when that `Host` is an IP address or `localhost`. Both rules
  are needed: the first keeps another page that happens to be open in your browser from
  attaching to your development server, and the second keeps a name that resolves to your
  loopback address from satisfying the first. A refused handshake is answered with `403` and
  the reason is printed to the terminal, repeated only when the reason changes — a refused
  browser reconnects forever, and would otherwise say so forever. There is nothing to
  configure, and the check is not
  authentication — it identifies the page, not the person, and anyone who can reach the port
  can still read the site.
- Rebuilds do not clean the output directory. Deleting a page therefore leaves the HTML that
  was already built for it in place, and its URL keeps serving the old content; run
  `hirundo build --clean` to drop it.
- `config.yaml` is read once, at startup. Editing it while `serve` is running has no effect —
  stop the server and start it again to pick up the new settings.
- `serve` refuses to start when `build.outputDirectory` sits inside a watched directory (or
  contains one), because each rebuild would then trigger the next one forever.

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
| `--slug` | File name without the `.md` extension, used verbatim. Defaults to a slug derived from the title. `index` is reserved for posts. |
| `--categories` | Comma-separated. Blank entries and duplicates are dropped. Control characters and line breaks are rejected. |
| `--tags` | Comma-separated. Blank entries and duplicates are dropped. Control characters and line breaks are rejected. |
| `--template` | Value for the `template:` key. Defaults to `post.html`. Control characters and line breaks are rejected. |
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
| `--path` | Path relative to the content directory. `--path about/team` creates `content/about/team.md`, intermediate directories included. Defaults to a slug derived from the title. Each component is limited to `limits.maxFilenameLength` characters (255 by default); an over-long one is rejected. A deep chain of short names is fine. |
| `--template` | Value for the `template:` key. Defaults to `default.html`. Control characters and line breaks are rejected. |
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
  What is rejected: `/`, `\`, `.`, `..`, control characters, a blank value, and anything
  over the file name limit.
- **`index` is reserved for posts.** `content/posts/index.md` would publish at `/posts/`
  while its RSS link would be built from the slug and point at `/posts/index/`, so both
  `--slug index` and a title that slugifies to `index` are refused. Pages are unaffected:
  `content/index.md` is the home page `hirundo init` writes, `content/about/index.md`
  legitimately publishes at `/about/`, and pages are not in the feed.
- `--categories`, `--tags`, and `--template` are written into the frontmatter as quoted
  values, so control characters and line breaks are rejected before anything is created —
  they would otherwise make the generated file fail to parse at build time.
- `--open` only runs editors on an allow-list (`vim`, `nvim`, `nano`, `emacs`, `code`,
  `subl`, `vi`, `open`, and similar) and never goes through a shell. The name is run on
  its own, so a value carrying arguments (`code --wait`, `vim +startinsert`) is refused,
  as is an absolute path outside a small fixed list. What runs is what was checked: an
  allowed absolute path (`/usr/bin/vim`) is executed as that exact file, and only a bare
  name (`vim`) is looked up on `PATH`.
  If `$EDITOR` is unset, refused, or fails to start, the command prints a warning and
  still exits 0 — the file has already been written. The warning distinguishes "nothing
  set" from "set but refused", and names the refused value.
  While the editor runs it owns the terminal, so a full-screen editor draws normally and
  Ctrl-Z suspends the job as it would for any other command: `hirundo` stops alongside the
  editor, the shell gets the terminal back and prints its prompt, and `fg` resumes both.

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

### `hirundo validate`
Check the configuration file without building anything.

```bash
hirundo validate [options]

Options:
  --config <file>  Configuration file path (default: config.yaml)
  --verbose        Show verbose error information
```

It reports two different kinds of problem. A file that cannot be decoded is an **error**: the
command exits non-zero and names the key at fault — `Missing required field: site.url`,
`Invalid configuration value: blog.postsPerPage: expected Int`. A file that decodes but
contains keys Hirundo does not act on — a typo, or a block that was never wired up such as
[`timeouts` or `server.cors`](#not-yet-implemented) — is a **warning** on stderr and still
exits 0, because silently ignoring those keys is what the parser genuinely does.

Keys are checked at the top level and one level in (`features.sitemp` is caught); nothing
deeper than that is inspected.

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

`config.yaml` has exactly seven top-level keys: `site`, `build`, `server`, `blog`, `features`,
`limits`, and `assets`. Only `site` is required; every other block falls back to its defaults.

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

# Built-in feature flags. A mapping, not a list. Omit the block and all five are false.
features:
  sitemap: true
  rss: true
  searchIndex: true
  minify: true
  fingerprint: true

# Security and performance limits. Every key is optional; the values below are the defaults.
limits:
  maxMarkdownFileSize: 10485760     # 10MB
  maxFrontMatterSize: 100000        # 100KB
  maxFilenameLength: 255
  maxTitleLength: 200
  maxDescriptionLength: 500
  maxUrlLength: 2000
  maxAuthorNameLength: 100
  maxEmailLength: 254
  maxLanguageCodeLength: 35

# Extra fingerprint exclusions, added to the built-in list (see Built-in Features below).
# Optional; omit the block entirely if you have none.
assets:
  fingerprintExclude:
    - "apple-touch-icon*.png"
    - "ads.txt"
```

A minimal configuration is just the two required fields:

```yaml
site:
  title: "My Site"
  url: "https://example.com"
```

### Gotchas

- **Every optional block takes a subset of its keys.** `features`, `limits`, `assets`,
  `build`, `server` and `blog` each default the keys you leave out, so raising one limit means
  writing one line, not restating the other eight. `hirundo validate` reports keys that are not
  recognized.
- **Values are validated, not just decoded.** `site.url` must be a URL with a scheme and a
  host, `site.language` must be a well-formed BCP 47 tag (`en`, `en-US`, `zh-Hans`),
  `site.author.email` must be an e-mail address, and every `limits` value must be a positive
  integer. A configuration that breaks one of these fails the build rather than being
  accepted and quietly ignored. Note that the `site.*` length caps (title, description,
  URL, author name, e-mail, and language code) **are** taken from the `limits` block —
  `maxTitleLength`, `maxDescriptionLength`, `maxUrlLength`, `maxAuthorNameLength`,
  `maxEmailLength` and `maxLanguageCodeLength` — with the defaults shown above (200, 500,
  2000, 100, 254, 35) applying when `limits` is omitted.
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
| `features` | all five false |
| `limits` | the values shown in the example above |
| `assets` | no extra exclusion patterns — the built-in list still applies |

`hirundo init` writes everything through `features` and omits both `limits` and `assets`,
which therefore run on their defaults — the built-in fingerprint exclusions apply even with
no `assets:` block in the file.

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

Hirundo ships five built-in features, toggled by the `features` block. Dynamic loading of
external code is not supported, for security and simplicity.

| Flag | Effect |
|------|--------|
| `sitemap` | Writes `sitemap.xml` to the output root |
| `rss` | Writes `rss.xml` from your posts |
| `searchIndex` | Writes `search-index.json` for client-side search |
| `minify` | Enables CSS and JS minification in the asset pipeline |
| `fingerprint` | Adds a content hash to asset names and rewrites HTML/CSS references to match |

Note that `minify` applies to **CSS and JS assets only** — generated HTML is not minified.

The asset pipeline reads from `static/` and follows a symbolic link only while it resolves
*inside* `static/`. A link that points outside is skipped with a warning on stderr, so
`static/vendor -> ../node_modules/pkg/dist` publishes nothing and `static/leak.txt -> /etc/passwd`
cannot copy its target into the built site. Copy or vendor the files you want published. A
link that resolves inside `static/` is materialized as a regular file in the output; a broken
link fails the build rather than being skipped silently.

Enabling `fingerprint` writes most `static/` assets under content-hashed names, such as
`style-9f2a1c04b7e3d5a1.css`, and rewrites the generated HTML's `href` / `src` / `srcset`,
CSS `url(...)` and `@import`, `<style>` bodies, and `style` attributes to point at those
names. The mapping is written to `_site/asset-manifest.json`. Output from older hashed names
is removed on every build — from the current `static/` tree *and* from the previous build's
manifest, so an asset whose whole directory was deleted from `static/` stops being served —
so output does not grow without bound even under `hirundo serve`'s non-clean rebuilds.
Only hashed names are pruned: an *excluded* asset deleted from `static/` lingers in the
output until a clean build, because removing an unhashed path risks deleting a generated
page that happens to sit at the same path.
That pruning only runs while the flag is on, though: turning `fingerprint` back off does
**not** remove output already written under a hashed name, since nothing prunes it any more.
Run `hirundo build --clean` after changing the flag in either direction.

A handful of assets are excluded from fingerprinting — see [Excluding assets from
fingerprinting](#excluding-assets-from-fingerprinting) below.

There are several limitations:

- **Only `href`, `src`, and `srcset` are rewritten as URL-bearing HTML attributes**, plus
  `style` attribute values and `<style>` element bodies, which go through the same CSS
  `url(...)` rewriter as `.css` files. No other attribute — `data-src`, `poster`,
  `background`, and the like — is inspected, even where a browser would load an asset
  through it.
- **A reference is matched against the manifest literally, with no percent-decoding.** A
  percent-encoded path such as `/images/my%20photo.jpg` does not match the manifest entry for
  an asset stored as `images/my photo.jpg`; it is left unchanged and, once the target has
  been renamed to its hashed form, becomes a dead link. This is one instance of a general
  rule: a reference that fails to resolve against the manifest is passed through silently by
  design. The build does not warn about it — a stylesheet reference that resolves to nothing,
  described below, is the one exception that does.
- **References inside JavaScript are not rewritten.** Whether a string like
  `fetch("/images/logo.png")` is a reference cannot be determined statically. Read
  `asset-manifest.json` if you need to reference an asset from JavaScript.
- **Stylesheets that import each other keep their original names.** A CSS-to-CSS reference
  — `@import url("other.css")` or the bare `@import "other.css"` — is rewritten normally,
  because stylesheets are processed in dependency order, so a stylesheet's hashed name is
  already known by the time another one references it. Stylesheets that import each other,
  or themselves, admit no such order: those keep their original names and their references
  are left alone, which keeps them resolving. A reference that resolves to no stylesheet at
  all prints a warning.
- **Well-known filenames are excluded from fingerprinting automatically.** `robots.txt`,
  `sitemap.xml`, `favicon.ico`, `CNAME`, `_headers`, `_redirects`, `.htaccess`, `ads.txt`,
  `app-ads.txt`, `sw.js`, `service-worker.js`, and everything under `.well-known/` are
  fetched under a fixed URL that no page ever references, so nothing would rewrite a
  reference to them; fingerprinting them would serve each only under its hashed name and
  turn every request for the well-known name into a 404. These built-ins need no
  configuration. Add more patterns under `assets.fingerprintExclude` — see
  [Excluding assets from fingerprinting](#excluding-assets-from-fingerprinting) below.

### Excluding assets from fingerprinting

The built-in list above — `robots.txt`, `sitemap.xml`, `favicon.ico`, `CNAME`, `_headers`,
`_redirects`, `.htaccess`, `ads.txt`, `app-ads.txt`, `sw.js`, `service-worker.js`, and
`.well-known/**` — is always applied, whether or not `config.yaml` has an `assets:` block.
To exclude more files, list patterns under `assets.fingerprintExclude`:

```yaml
assets:
  fingerprintExclude:
    - "apple-touch-icon*.png"
    - "browserconfig.xml"
```

Patterns are **added** to the built-in list; they cannot remove one of the built-ins. An
excluded asset is written under its original name and appears in the manifest mapped to
itself, so any reference to it keeps working and the pruner does not treat it as stale
output from a previous build.

Patterns are matched against the asset's path relative to the `static/` directory, with `/`
as the separator; that path never starts with a `/`, so patterns carry no leading slash —
a leading `/` or `./` you write is stripped before matching (`/robots.txt` and `robots.txt`
behave the same):

- a pattern with no `/` matches the file name at any depth (`ads.txt` matches both `ads.txt`
  and `vendor/ads.txt`). The built-ins are all of this form, deliberately: `.htaccess` is
  read by Apache in *every* directory, and a service worker registered from JavaScript is
  scoped by whatever path it is served from
- a pattern with a `/` matches the whole relative path (`css/style.css` does not match
  `deep/css/style.css`)
- `*` matches within a single path segment and never crosses a `/`
- `**` as a whole path segment matches any number of segments, including zero
- everything else is literal. Matching is case-sensitive, and there is no `?`, no character
  class, no escaping, and no negation.

Archive, category, and tag pages are controlled separately, by the `blog` block.

## Not Yet Implemented

These are documented here because earlier versions of this README described them as working.
They are not:

- **CORS configuration.** There is no `server.cors` block. `server` accepts only `port` and
  `liveReload`; a `cors:` key under it is silently ignored.
- **Timeout configuration.** There is no `timeouts` block and no configurable timeouts for
  file, directory, HTTP, file-watching, or server-start operations.
- **Plugin architecture.** The plugin system was removed; the five flags under `features`
  replace it. There is no custom-plugin development support, and no `imageOptimization` or
  `syntaxHighlight` feature.
- **WebSocket authentication for live reload.** There is no `/auth-token` endpoint, no token
  handshake, and nothing to configure. `/livereload` is guarded by an `Origin`/`Host` check
  (see [`hirundo serve`](#hirundo-serve)), which keeps other pages in your browser out but
  identifies no one: anyone who can reach the port can read the site, and can reach live
  reload too by opening the site by IP address. Do not expose the development server to an
  untrusted network.
- **Asset concatenation and source maps.** JS/CSS concatenation and source map generation
  have been removed, `AssetConcatenator` and all, along with the `sourceMap` option. JS
  transpilation (`transpile` / `target`) is gone the same way. Use Babel or esbuild for
  ES6+ transforms.
- **`layout:` in frontmatter.** Use `template:`.

`hirundo validate` reports every key in this list that your `config.yaml` sets.

## Security

Hirundo implements security measures appropriate to a static site generator:

- **Input validation**: configurable size limits for Markdown files, the config file, and
  frontmatter; length limits on titles, descriptions, URLs, author names, e-mail addresses,
  and language codes.
- **Path validation**: `build` directories may not be absolute or contain `..`; the
  development server rejects request paths that escape the output directory.
- **Asset processing**: CSS/JS processing with optional minification.
- **Development server**: the live-reload handshake is accepted only from a same-origin page
  that reached the server by address; WebSocket session cleanup and file-watcher teardown on
  shutdown.

See [SECURITY.md](SECURITY.md) for the security policy.

### Local Verification with Fixture

You can verify end-to-end using the provided fixture:

```bash
cd test-hirundo
swift run --package-path .. hirundo build --clean
swift run --package-path .. hirundo serve
# open http://127.0.0.1:8080 and edit files under test-hirundo/content/
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

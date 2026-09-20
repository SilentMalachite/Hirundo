# Security Policy

## Supported Versions

We actively maintain and provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security vulnerability in Hirundo, please report it privately.

### How to Report

1. **Do not** create a public GitHub issue for security vulnerabilities
2. Send an email to: [security@hirundo.dev] (or the maintainer's email)
3. Include the following information:
   - Description of the vulnerability
   - Steps to reproduce the issue
   - Potential impact
   - Suggested fix (if available)

### Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity, typically within 30 days for critical issues

### Security Measures in Hirundo

Hirundo includes basic security measures appropriate for a static site generator:

#### Input Validation
- **File Size Limits**: Configurable limits for configuration and content files
- **Basic Path Handling**: Standard Swift file operations with proper error handling
- **Content Processing**: Safe processing of markdown and template content

#### File Operations
- **Standard APIs**: Uses Swift's built-in file operations with proper error handling
- **Resource Management**: Automatic cleanup of file handles and resources
- **Transpilation Disabled**: Potentially unsafe JS transpilation disabled by default
- **File Type Validation**: Strict file type checking and processing
- **Build-Output Confinement**: Every generated file is written inside the configured
  output directory. The destination's parent is resolved and checked; the last
  component never is, so a symbolic link sitting where a file is about to be written
  is removed rather than followed, and an output tree left holding links from an
  earlier build repairs itself instead of leaking the write to the link's target. An
  intermediate directory that resolves outside is refused. `--clean` empties the
  output directory rather than removing it, so a deliberately symlinked output root
  is left intact and its target is not deleted
- **Source Confinement**: A symbolic link under `static/` is followed only while it
  resolves inside `static/`, and the containment check is repeated immediately before
  the file is read

#### Content Rendering
- **Constructed, Not Filtered**: `HTMLRenderer` builds every tag itself from the
  Markdown tree. It has no case for `HTMLBlock` or `InlineHTML`, both of which are
  leaves, so raw HTML in a Markdown source renders to nothing rather than being
  filtered after the fact
- **Attribute Escaping**: Every author-controlled value reaching an attribute is
  escaped, including the fenced code block's language, link and image URLs, `title`
  and `alt`
- **URL Schemes**: Link and image URLs are limited to http, https, mailto, ftp and
  ftps; anything else becomes `#`
- **Known Limitation**: `HTMLSanitizer` is a defence-in-depth pass over markup the
  renderer already produced, not a sanitizer for untrusted HTML. Pointed at arbitrary
  input it would let `<iframe>`, `<object>`, `<form>` and unquoted attribute values
  through. Do not use it as one
- **One Escape Table**: `HTMLEscaping.escaped` is the single rule for turning a value
  into markup that means the value. Everything that builds HTML by interpolation uses
  it — the renderer, and the built-in archive, category and tag pages
- **`search-index.json` Holds Text, Not Markup**: with `features.searchIndex` on, a
  page's title and its category and tag names are written to the index as the author
  wrote them. That is correct for JSON — escaping them there would show a searcher
  `&lt;b&gt;` — but it makes the search UI responsible for the last step. Insert a
  result with `textContent`, never `innerHTML`. Hirundo ships no search UI, so this is
  a contract with whatever consumes the file

#### Input Validation Is Not The Boundary
- **What It Is**: `MarkdownValidator` rejects a file containing any of twelve
  lowercased substrings (`<script`, `javascript:`, `onerror=` and nine more). It fails
  a build early. It is not a gate
- **What Walks Past It**: `<iframe`, `<object`, `<embed`, `onpointerover=`,
  `ontoggle=`, `onwheel=`, and `onerror =` with a space before the equals. The list
  cannot be completed, and lengthening it costs real false positives — `onclick=` as a
  string, in an article about XSS, already fails a build
- **What It Never Sees**: `config.yaml` — `site.title` and `site.author.name` are
  checked for length and nothing else — and file names, which become URLs. A macOS file
  may be named `a"onmouseover="alert(1).md`
- **Where The Boundary Is**: the output side. `HTMLRenderer` constructs its own tags,
  every interpolated value goes through `HTMLEscaping.escaped`, and templates escape
  with the `escape` filter

#### Template Escaping
- **No Autoescaping**: Stencil has none, and the mechanism does not exist in the
  library — a template's `{{ … }}` is written out as it stands. Escaping is the
  template author's responsibility
- **The `escape` Filter**: `{{ value|escape }}`, with `e` as an alias. The templates
  `hirundo init` writes apply it to every value they interpolate except `{{ content }}`
- **Never On Rendered HTML**: `{{ content }}` and the `markdown` filter's output are
  already HTML, and escaping is not idempotent, so escaping them shows a reader the
  page's own source
- **Opt-In For Existing Sites**: upgrading Hirundo does not rewrite templates a site
  already has. A template written before this filter existed still interpolates raw

#### Development Server Security
- **Basic WebSocket**: Simple live reload functionality on `/livereload`
- **Handshake Screening**: `/livereload` is accepted only when `Host` is an IP
  literal or `localhost` and `Origin` is an http(s) URL whose host and port match
  that `Host`; anything else is answered with `403` and a sanitized reason on
  stderr, repeated only when the reason changes so that a refused browser
  reconnecting forever reports itself once. The `Origin` rule keeps another page
  open in the developer's browser
  from attaching to the server (cross-site WebSocket hijacking); the `Host` rule
  keeps a name pointed at the loopback address from satisfying it (DNS rebinding)
- **Output-Directory Confinement**: Requests whose resolved path falls outside
  the configured output directory are rejected
- **Error Handling**: Proper error reporting without sensitive information leakage

There is no CORS configuration and no WebSocket authentication; the server is
intended for local development only. The handshake check above is a same-origin
check, not authentication: it has no token and no configuration, and it does not
identify who is connecting. Anyone who can reach the port can read the served
site, and can reach live reload as well by addressing the server by IP.

## Security Configuration

### Recommended Settings

The configuration file's own size cap is not a `limits` key — a file cannot declare its own
limit — but a fixed 1 MB ceiling enforced when `config.yaml` is read.

```yaml
# Basic limits for content files
limits:
  maxMarkdownFileSize: 1048576      # 1MB
  maxFrontMatterSize: 10240         # 10KB
  maxFilenameLength: 200            # Reasonable limit
  maxTitleLength: 100               # SEO-friendly limit
  maxDescriptionLength: 300         # Meta description limit

# Feature configuration
features:
  minify: true
```

### Security Checklist

Before deploying Hirundo in production:

- [ ] Review and configure file size limits in `config.yaml`
- [ ] Decide whether `features.minify` should be on — it enables CSS *and* JS
      minification together; there is no separate JS toggle
- [ ] Validate all content sources and inputs
- [ ] Use HTTPS for the production site
- [ ] Regularly update Hirundo and its dependencies
- [ ] Monitor build logs for security warnings
- [ ] Implement proper file permissions on the server

## Security Notes (2025-08-17)

Hirundo focuses on the minimal, appropriate safeguards for a static site generator. There is no dynamic execution of untrusted code.

- Path handling uses standard Swift file APIs with proper error propagation.
- WebSocket live-reload is basic and scoped to local development. Its handshake is
  screened by `Origin`/`Host` so that only the page this server served can connect;
  that is not authentication and does not make the server safe to expose.
- There is no plugin system at all. It was removed in Stage 2 and replaced by
  compiled-in feature toggles (`features:` in `config.yaml`), so there is no
  dynamic loading path to secure.
- There is no configurable timeout system; `config.yaml` has no `timeouts` block.

Testing & Validation:
- Security-relevant behavior is covered by existing unit/integration tests where applicable. We do not claim a separate “security test suite” size.

## Security Announcements

Security updates and announcements will be published:

- In GitHub Security Advisories
- In the CHANGELOG.md file
- On the project's main page
- Through GitHub Releases with security tags

## Acknowledgments

We appreciate security researchers and users who help keep Hirundo secure. Responsible disclosure helps protect all users.

### Hall of Fame

*Contributors who have helped improve Hirundo's security will be listed here (with their permission).*

## Security Best Practices for Users

### Content Security
1. **Validate Content Sources**: Only process trusted markdown files
2. **Review Frontmatter**: Check YAML frontmatter for suspicious content
3. **Limit File Sizes**: Use appropriate limits for your use case
4. **Monitor Build Output**: Review generated HTML for unexpected content

### Deployment Security
1. **HTTPS Only**: Always serve generated sites over HTTPS
2. **Content Security Policy**: Implement appropriate CSP headers
3. **File Permissions**: Set restrictive permissions on generated files
4. **Regular Updates**: Keep Hirundo and dependencies updated

### Development Security
1. **Trusted Sources**: Only use templates and static assets from trusted
   sources — Hirundo renders whatever is in `templates/` and copies whatever is
   in `static/`
2. **Code Review**: Review any custom code or configurations
3. **Environment Separation**: Keep development and production environments separate
4. **Backup Strategy**: Maintain secure backups of your site content

For more security guidance, see our [security documentation](docs/security.md) (when available).

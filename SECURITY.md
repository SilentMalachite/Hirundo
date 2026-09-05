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

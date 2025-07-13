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

Hirundo includes several built-in security measures:

#### Input Validation
- **File Size Limits**: Configurable limits prevent DoS attacks through large files
- **Path Validation**: Comprehensive protection against path traversal attacks
- **Content Sanitization**: Safe processing of user-generated content
- **Frontmatter Validation**: YAML parsing with size and complexity limits

#### Path Security
- **Traversal Protection**: Advanced detection and prevention of `../` attacks
- **Symlink Resolution**: Safe handling of symbolic links
- **Sandboxing**: File operations restricted to project directories
- **Path Sanitization**: Comprehensive cleaning of file paths

#### Asset Processing Security
- **CSS/JS Validation**: Syntax validation before processing
- **Minification Safety**: Safe minification without code injection risks
- **Transpilation Disabled**: Potentially unsafe JS transpilation disabled by default
- **File Type Validation**: Strict file type checking and processing

#### Development Server Security
- **WebSocket Protection**: Memory-safe session management
- **Error Isolation**: Secure error reporting without information leakage
- **Rate Limiting**: Built-in protection against resource exhaustion
- **CORS Configuration**: Proper handling of cross-origin requests

#### Memory Safety
- **Resource Management**: Automatic cleanup of file handles and connections
- **Memory Limits**: Configurable limits to prevent memory exhaustion
- **Leak Prevention**: Advanced WebSocket session cleanup
- **Buffer Management**: Safe handling of large file processing

## Security Configuration

### Recommended Settings

```yaml
# Security limits (recommended for production)
limits:
  maxMarkdownFileSize: 1048576      # 1MB (stricter than default)
  maxConfigFileSize: 102400         # 100KB (stricter than default)
  maxFrontMatterSize: 10240         # 10KB (stricter than default)
  maxFilenameLength: 200            # Reasonable limit
  maxTitleLength: 100               # SEO-friendly limit
  maxDescriptionLength: 300         # Meta description limit

# Plugin security
plugins:
  - name: "minify"
    enabled: true
    settings:
      minifyHTML: true
      minifyCSS: true
      minifyJS: false  # Keep disabled for security
```

### Security Checklist

Before deploying Hirundo in production:

- [ ] Review and configure security limits in `config.yaml`
- [ ] Ensure JS transpilation remains disabled unless absolutely necessary
- [ ] Validate all content sources and inputs
- [ ] Use HTTPS for the production site
- [ ] Regularly update Hirundo and its dependencies
- [ ] Monitor build logs for security warnings
- [ ] Implement proper file permissions on the server

## Security Announcements

Security updates and announcements will be published:

- In GitHub Security Advisories
- In the CHANGELOG.md file
- On the project's main page

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
1. **Trusted Sources**: Only use plugins and themes from trusted sources
2. **Code Review**: Review any custom code or configurations
3. **Environment Separation**: Keep development and production environments separate
4. **Backup Strategy**: Maintain secure backups of your site content

For more security guidance, see our [security documentation](docs/security.md) (when available).
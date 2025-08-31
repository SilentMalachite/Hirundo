## Hirundo v1.1.0 (2025-08-31)

This release focuses on simplification, safety, and clarity.

### Highlights

- Features, not plugins: The old plugin system was removed. Built-in capabilities (sitemap, RSS, search index, minify) are now configured via `features:` in `config.yaml`.
- Concurrency cleanup: Eliminated TemplateCache Sendable warnings by replacing GCD-based captures with a lock-based, opportunistic cleanup design.
- Documentation refresh: README/README.ja/SECURITY updated to reflect `features:`; ARCHITECTURE now describes built-in features instead of plugins.

### Migration Notes

- Replace any `plugins:` configuration with:

```yaml
features:
  sitemap: true
  rss: true
  searchIndex: true
  minify: true
```

- No dynamic loading: External plugins are no longer supported.

### Changes

- Removed: Plugin APIs (Plugin/PluginManager/PluginManifest and built-in plugin files)
- Added: `features:` configuration (sitemap/rss/searchIndex/minify)
- Fixed: TemplateCache Sendable warnings (no @Sendable GCD captures)
- Docs: Updated examples and guides to use `features:`

### Thanks

Thanks to all contributors who helped streamline Hirundo and improve the developer experience.


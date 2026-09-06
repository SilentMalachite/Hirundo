# Task 7 — documentation report

## Verification against source (before writing anything)

Read `Sources/HirundoCore/Assets/AssetFingerprintExclusions.swift`,
`Sources/HirundoCore/AssetPipeline.swift`, `Sources/HirundoCore/SiteGenerator.swift`,
`Sources/HirundoCore/Models/Assets.swift`, `Sources/HirundoCore/Models/Config.swift`,
`Sources/HirundoCore/ConfigDiagnostics.swift`, `Sources/HirundoCore/Assets/AssetPruner.swift`,
and `Sources/HirundoCore/Scaffold/ScaffoldTemplates.swift`, plus the diffs of commits
`faae2c0` and `a5f6ea6`. Every claim in the brief checked out exactly:

- Built-in exclusion list is `robots.txt`, `favicon.ico`, `CNAME`, `_headers`, `_redirects`,
  `.htaccess`, `.well-known/**` (`AssetFingerprintExclusions.builtIn`), applied unconditionally
  before any config is consulted.
- `assets.fingerprintExclude` patterns are appended to the built-ins in
  `AssetFingerprintExclusions.init(additional:)`; there is no way to remove a built-in.
- Pattern language (`AssetFingerprintExclusions.matches`/`matchSegments`/`matchSegment`)
  matches the brief exactly: no-`/` patterns match the last path component at any depth;
  `/`-containing patterns match the whole path; `*` is bounded to one segment; `**` as a whole
  segment matches zero or more segments (with adjacent-`**` collapsing for performance);
  matching is case-sensitive string comparison — no `?`, character class, escaping, or
  negation exist anywhere in the type.
- `AssetPipeline.write` skips fingerprinting when `fingerprintExclusions.excludes(relativePath)`
  is true, leaving `outputRelativePath == relativePath`; `manifest[relativePath] =
  outputRelativePath` then maps the excluded asset to itself.
- `AssetPruner.prune` now calls `fileManager.contentsOfDirectory(atPath:)` with `try` (not
  `try?`) at both call sites (fixed in `faae2c0`), so a directory it cannot read now throws
  and reaches `SiteGenerator` as a `.writing` build error instead of pruning nothing silently.
- `SiteGenerator.rewriteAssetReferences` (pass 3) now calls `warn(...)` to stderr on an
  unreadable file's resource values and on non-UTF-8 content, instead of silently `continue`-ing
  (fixed in `faae2c0`).
- `AssetPipeline.write` copies pass-through content via `FileManager.copyItem` (preserving
  permissions/xattrs, letting APFS clone) instead of `Data.write` of an in-memory read, and
  streams the hash via `AssetProcessor.generateFingerprint(for: URL)` (fixed in `a5f6ea6`).
- `HirundoConfig` (`Models/Config.swift`) has exactly 7 `CodingKeys` cases: `site`, `build`,
  `server`, `blog`, `features`, `limits`, `assets`.
- `ScaffoldTemplates.configYAML` writes `site`/`build`/`server`/`blog`/`features` only — no
  `assets:` block — confirming `hirundo init` does not emit one.
- `ConfigDiagnostics.recognizedTopLevelKeys` and `recognizedKeysByBlock` are derived from
  `HirundoConfig.CodingKeys.allCases` and `Assets.CodingKeys.allCases`, so `assets` and
  `assets.fingerprintExclude` are recognized automatically with no hand-written addition.
- `SiteGenerator.processStaticAssets` only calls `AssetPruner.prune` inside
  `guard config.features.fingerprint else { return }`, confirming pruning — and thus removal
  of stale hashed output — stops entirely when the flag is off, matching the still-true
  limitation the brief said not to delete.

No sentence the brief asked me to write turned out to be false against the shipped code.

## Sweep

Patterns searched across every root-level `*.md` file (`README.md`, `README.ja.md`,
`CLAUDE.md`, `ARCHITECTURE.md`, `AGENTS.md`, `CHANGELOG.md`, `CONTRIBUTING.md`,
`SECURITY.md`, `TESTING.md`, `DEVELOPMENT.md`, `DEPENDENCY_UPDATE_NOTES.md`, `TODO.md`):

1. `six top-level\|exactly six\|の6つ\|6つのみ` — hits: `CLAUDE.md:157`, `AGENTS.md:41`,
   `ARCHITECTURE.md:222`, `README.ja.md:353-354`, `README.md:21,353`. All fixed to seven and
   `assets` added to the enumeration (`AGENTS.md` was not in the brief's file list but carried
   the identical false claim, so I fixed it too — it's root-level documentation the sweep is
   explicitly scoped to catch).
2. `renames every file\|every static file\|全ての静的ファイル\|すべての静的ファイル` — hit:
   `README.md:580` (the warning the brief named). Replaced in place with the built-in list +
   `assets.fingerprintExclude` escape hatch, per the brief. The Japanese equivalent
   (`README.ja.md:576-582`, worded as "フィンガープリントは `static/` 配下のすべてのファイルを
   改名します") was caught by manual comparison against the English section (not literally
   matched by this grep pattern's exact Japanese wording) and fixed the same way.
3. `sitemap.*rss.*searchIndex.*minify\|sitemap / rss / searchIndex / minify` (feature-flag
   enumerations that might predate `fingerprint`/`assets`) — hits in `CLAUDE.md:12` and
   `README.md`/`.ja.md` tables all already included `fingerprint`; none predated it. No config
   surface change needed there, but I added a note to `fingerprint`'s bullet in both `README`
   files and `CLAUDE.md` pointing at the exclusion mechanism, since `features.fingerprint`'s own
   behavior changed.
4. `site.*build.*server.*blog` / literal top-level key lists — same hits as #1, already fixed.
5. `assets:` (finding every existing mention, to make sure nothing needed reconciling) — zero
   hits anywhere before this task's edits.
6. `AssetItem` in `CHANGELOG.md` `### Removed` — confirmed present (line 41 in the pre-edit
   file) and left untouched, not duplicated.
7. Broader check of `docs/superpowers/**` — found only planning/spec documents from earlier in
   this branch (not shipped, not root-level, not user-facing); left alone as historical
   artifacts, not "documentation" the brief's sweep is asking about.
8. Checked `CONTRIBUTING.md`'s `Features` struct example (`sitemap`/`rss`/`searchIndex`/
   `minify`/`fingerprint` booleans) — still accurate; `Assets` is a separate top-level struct,
   not a `Features` field, so no change needed there.
9. Checked `SECURITY.md`'s example `config.yaml` and checklist — a partial example, not an
   exhaustive-key claim; not a hit.

One out-of-scope finding, not fixed: `AGENTS.md:37` says `swift test` has "既知の失敗
（HotReloadManagerTests の 6 件）" (six known failures). The current baseline run has 0
failures (see below), and `CHANGELOG.md`'s own `### Fixed` entry documents that fix as already
landed. This predates the fingerprint-exclusions work specifically (it's about file-watching,
unrelated to fingerprinting or the config schema) and is outside what this brief's sweep asked
me to search for (config-key enumerations and fingerprint-renames-everything claims), so I did
not touch it — flagging it here since it is a stale/false claim I noticed in root-level docs.

## Files changed

- `README.md` — top-level key count (6→7) in two places, `assets:` added to the config
  example, gotchas bullet, defaults table, `hirundo init` sentence; the false fingerprinting
  warning replaced with an accurate bullet plus a new "Excluding assets from fingerprinting"
  subsection documenting the built-in list, `assets.fingerprintExclude`, and the full pattern
  language.
- `README.ja.md` — same set of changes, written as natural Japanese matching the file's
  existing measured/factual register, including a matching `### フィンガープリントからの
  アセット除外` subsection.
- `CLAUDE.md` — top-level key count and enumeration (6→7, `assets` added) in the "主な機能"
  bullet list and the `config.yaml` schema section; `assets:` added to the YAML example and
  the "各ブロックのデフォルト値" table; the `fingerprint` feature-flag bullet now names the
  built-in exclusions and points at `assets.fingerprintExclude`.
- `ARCHITECTURE.md` — Asset Pipeline section: fixed the now-false "`features.minify` and
  `features.fingerprint` are the only asset-related settings" claim, added a paragraph
  describing `AssetFingerprintExclusions`/`assets.fingerprintExclude` and the pattern rules,
  and folded in the pruner-error and pass-through-copy fixes since they're the same code path
  already described there. Configuration System section: six→seven top-level keys, `assets`
  added to the `HirundoConfig` tree diagram.
- `CHANGELOG.md` under `[Unreleased]`: three new `### Fixed` bullets (pruner directory-read
  error, pass-3 stderr warning, pass-through copy-not-rewrite) and one new `### Added` bullet
  (built-in exclusions + `assets.fingerprintExclude` + pattern language). Left the existing
  `### Removed` `AssetItem` entry untouched, as instructed.
- `AGENTS.md` — fixed the same six-top-level-keys claim found by the sweep (not in the brief's
  file list, but a root-level doc carrying the exact false claim the sweep was told to look
  for).

## Build and test

- `swift build`: clean, `Build complete!` — matches baseline.
- `swift test`: 645 tests, 0 failures — identical to the stated baseline (645/0). Suite count
  did not move.
- `git diff --name-only -- Sources Tests`: empty. No file under `Sources/` or `Tests/` changed.

## Concerns

- None of the brief's claims were found false against the shipped code; nothing needed to be
  reported as untrue.
- `AGENTS.md:37`'s stale "6 known HotReloadManagerTests failures" claim (see Sweep #7/finding
  above) is unrelated to fingerprinting/config-schema and outside this task's scope, so it was
  left as-is; worth a follow-up if anyone is tracking documentation staleness generally.

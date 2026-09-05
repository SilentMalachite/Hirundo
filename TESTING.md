# Testing Guide

This guide outlines how to run, structure, and extend tests in Hirundo.

## Running Tests

- Run all tests: `swift test`
- Filter by test case: `swift test --filter SiteGeneratorTests`
- Enable coverage: `swift test --enable-code-coverage`

### Current State of the Suite

`swift test` currently runs **210 tests with 6 failures**, all in
`HotReloadManagerTests`. These 6 are pre-existing — they fail on unmodified
`HEAD` too — and stem from FSEvents timing plus sandbox `.sb-` temporary-file
artifacts that break the tests' exact-path assertions. They are not yet fixed.

Treat them as the known baseline: a change is clean when it introduces no
failures beyond those 6.

## Naming and Structure

- Place tests under `Tests/HirundoTests/`.
- Use descriptive method names, e.g. `testGeneratesSite_whenDraftsEnabled_outputsDrafts()`.
- Derive from `XCTestCase` and keep fixtures small and focused.

## Coverage Expectations

- Cover all touched public APIs when modifying code.
- Include success and failure paths; assert error types and messages where applicable.
- Add edge and boundary cases for inputs and limits.

## Categories (reference)

The files that actually exist under `Tests/HirundoTests/`:

- AssetPipelineTests — asset processing and minification
- ConfigTests, ConfigParseTests — configuration validation and parsing
- MarkdownParserTests, SimpleMarkdownTest — markdown processing and validation
- SiteGeneratorTests — build orchestration and output
- TemplateEngineTests — Stencil rendering and custom filters
- SiteScaffolderTests, ScaffoldErrorMappingTests, InitDestinationResolverTests —
  `hirundo init` scaffolding, destination resolution, and error categorisation
- DevelopmentServerTests — static file serving and path resolution
- WebSocketOriginGuardTests, LiveReloadHandshakeTests — `Origin`/`Host` screening
  of the `/livereload` handshake, as a unit and end to end over a real socket
- HotReloadManagerTests, HotReloadIntegrationTest, FSEventsMemoryTests — file
  watching and live reload
- SecurityTests — security validation and protection
- ErrorRecoveryTests — error handling and partial-failure recovery
- EditorCommandValidationTests — editor command validation (command injection,
  path traversal, null bytes, control characters)
- DependencyCompatibilityTests — swift-markdown / Yams / Stencil behaviour
- IntegrationTests — end-to-end flows
- TestHelpers, ThreadSafeBox — shared test utilities, not test cases

## Integration Fixture

Use `test-hirundo` to verify end-to-end quickly:

```bash
cd test-hirundo
swift run --package-path .. hirundo build --clean
swift run --package-path .. hirundo serve
```

## Tips

- Prefer deterministic inputs and isolate filesystem state via temporary directories.
- Avoid flakiness: control timeouts and concurrency explicitly.
- Keep tests fast; mock heavy dependencies when reasonable.


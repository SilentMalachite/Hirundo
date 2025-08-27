# Testing Guide

This guide outlines how to run, structure, and extend tests in Hirundo.

## Running Tests

- Run all tests: `swift test`
- Filter by test case: `swift test --filter SecurityValidatorTests`
- Enable coverage: `swift test --enable-code-coverage`

## Naming and Structure

- Place tests under `Tests/HirundoTests/`.
- Use descriptive method names, e.g. `testGeneratesSite_whenDraftsEnabled_outputsDrafts()`.
- Derive from `XCTestCase` and keep fixtures small and focused.

## Coverage Expectations

- Cover all touched public APIs when modifying code.
- Include success and failure paths; assert error types and messages where applicable.
- Add edge and boundary cases for inputs and limits.

## Categories (reference)

- AssetPipelineTests — asset processing and minification
- ConfigTests — configuration validation and parsing
- ContentProcessor/MarkdownParserTests — markdown processing and validation
- EdgeCaseTests — error handling and edge scenarios
- Security*Tests — security validation and protection
- IntegrationTests — end-to-end flows
- WebSocketAuthenticationTests — live reload security

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


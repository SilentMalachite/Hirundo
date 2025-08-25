Coding style: Swift API Design Guidelines; 4-space indent; ~120 col line length; public APIs with `///` doc comments; Types UpperCamelCase, funcs/vars lowerCamelCase; prefer typed `Error` enums; `throws` for propagation; organize files by feature (Models, Plugins, Utilities).

Testing: XCTest; tests in `Tests/HirundoTests/` with *Tests.swift class names inheriting XCTestCase; naming example: `testGeneratesSite_whenDraftsEnabled_outputsDrafts()`. Cover public API and edge/error paths. Use `test-site/` fixtures for integration where helpful.

Security: no secrets in repo; site config via `config.yaml` validated; enforce limits on file sizes/timeouts; see SECURITY.md, WEBSOCKET_AUTHENTICATION.md.

Architecture: Executable defers to `HirundoCore`; new features go into core and surfaced via CLI.
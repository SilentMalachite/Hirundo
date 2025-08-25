Build: `swift build` (or `swift build -c release`)
Run CLI help: `swift run hirundo --help`
Serve with live reload: `swift run hirundo serve`
Build site: `swift run hirundo build --clean`
Run tests: `swift test`
Format (if needed): use SwiftFormat/SwiftLint if configured (not present in repo); otherwise keep to guidelines.

Darwin shell utils: `ls`, `rg` (ripgrep, preferred), `sed`, `open` for files on macOS.

After implementing changes: run `swift build` then `swift test`; if touching CLI, try `swift run hirundo build` on `test-site/` to smoke-test.
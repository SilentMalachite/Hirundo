import XCTest
@testable import HirundoCore

/// One row of the decision table below.
///
/// `file`/`line` are captured at the call site so a failing row points at the row itself rather
/// than at the single `XCTAssertEqual` inside the loop that checks all of them.
private struct Case {
    let name: String
    let origin: String?
    let host: String?
    let expected: WebSocketOriginGuard.Decision
    let file: StaticString
    let line: UInt

    init(
        _ name: String,
        origin: String?,
        host: String?,
        _ expected: WebSocketOriginGuard.Decision,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        self.name = name
        self.origin = origin
        self.host = host
        self.expected = expected
        self.file = file
        self.line = line
    }
}

final class WebSocketOriginGuardTests: XCTestCase {
    private let guardUnderTest = WebSocketOriginGuard()

    private func check(_ cases: [Case]) {
        for testCase in cases {
            let actual = guardUnderTest.evaluate(origin: testCase.origin, host: testCase.host)
            XCTAssertEqual(
                actual,
                testCase.expected,
                testCase.name,
                file: testCase.file,
                line: testCase.line
            )
        }
    }

    // MARK: - Allowed

    /// The ordinary case: the page and the socket address the server the same way, and that way
    /// is one the browser cannot have been tricked into by a DNS answer.
    func testEvaluate_whenOriginMatchesAnAddressLiteralHost_allows() {
        check([
            Case("localhost", origin: "http://localhost:8080", host: "localhost:8080", .allow),
            Case("IPv4 loopback", origin: "http://127.0.0.1:8080", host: "127.0.0.1:8080", .allow),
            Case("IPv6 loopback", origin: "http://[::1]:8080", host: "[::1]:8080", .allow),
            Case("LAN address", origin: "http://192.168.1.5:8080", host: "192.168.1.5:8080", .allow),
            Case("non-loopback IPv6", origin: "http://[fd00::1]:8080", host: "[fd00::1]:8080", .allow)
        ])
    }

    /// A host name is compared case-insensitively (RFC 3986 §3.2.2) and a URL that omits the port
    /// still has one — the scheme's default. Neither may be treated as a mismatch.
    func testEvaluate_whenOnlyCaseOrDefaultPortDiffers_allows() {
        check([
            Case("uppercase origin host", origin: "http://LOCALHOST:8080", host: "localhost:8080", .allow),
            Case("uppercase host header", origin: "http://localhost:8080", host: "LOCALHOST:8080", .allow),
            Case("uppercase scheme", origin: "HTTP://127.0.0.1:8080", host: "127.0.0.1:8080", .allow),
            Case("implicit port 80 on both sides", origin: "http://127.0.0.1", host: "127.0.0.1", .allow),
            Case("implicit port 80 on origin only", origin: "http://127.0.0.1", host: "127.0.0.1:80", .allow),
            Case("implicit port 443", origin: "https://127.0.0.1", host: "127.0.0.1:443", .allow)
        ])
    }

    /// Only the authority is compared, so an `https` origin naming the same host and port is
    /// accepted. That is not the same as supporting a proxy in front of the server, and the
    /// second row is here so the first cannot be read as promising one: an `https` origin that
    /// omits its port means 443, and no `Host` a plain-HTTP server is addressed by will match.
    func testEvaluate_whenOriginIsHTTPS_comparesTheAuthorityOnly() {
        check([
            Case("same authority", origin: "https://127.0.0.1:8443", host: "127.0.0.1:8443", .allow),
            Case(
                "implicit 443 against an implicit 80",
                origin: "https://127.0.0.1",
                host: "127.0.0.1",
                .deny(.originMismatch(origin: "127.0.0.1:443", host: "127.0.0.1:80"))
            )
        ])
    }

    /// The two headers are written from the same URL, so a browser spells an address the same
    /// way in both. Nothing tries to recognise that two spellings mean one address: comparing the
    /// text is what makes the rule easy to reason about, and the case it gives up on is one no
    /// browser produces.
    func testEvaluate_whenOneAddressIsSpelledTwoWays_denies() {
        check([
            Case(
                "expanded IPv6 against the compressed form",
                origin: "http://[::1]:8080",
                host: "[0:0:0:0:0:0:0:1]:8080",
                .deny(.originMismatch(origin: "[::1]:8080", host: "[0:0:0:0:0:0:0:1]:8080"))
            )
        ])
    }

    // MARK: - Denied: DNS rebinding

    /// The rebinding attack: the attacker's page is served from a name they control, that name is
    /// then re-pointed at 127.0.0.1, and the browser connects to us believing it is same-origin —
    /// so `Origin` and `Host` agree and an origin check alone waves it through. What gives it away
    /// is that a browser aimed at a development server addresses it by literal address, never by a
    /// name, so any name in `Host` means the connection was routed by a resolver we do not trust.
    func testEvaluate_whenHostHeaderIsAName_deniesAsRebinding() {
        check([
            Case(
                "rebound attacker domain",
                origin: "http://evil.example:8080",
                host: "evil.example:8080",
                .deny(.hostNotAddressLiteral("evil.example"))
            ),
            Case(
                "mDNS name",
                origin: "http://mymac.local:8080",
                host: "mymac.local:8080",
                .deny(.hostNotAddressLiteral("mymac.local"))
            ),
            Case(
                "name in host, literal in origin",
                origin: "http://127.0.0.1:8080",
                host: "evil.example:8080",
                .deny(.hostNotAddressLiteral("evil.example"))
            )
        ])
    }

    // MARK: - Denied: parser tricks

    /// `URLComponents` reports a host it has already decoded and folded, and an address check
    /// built on the result rather than on what the header said is a check that can be talked out
    /// of its answer. The first row is the one that bites: `%00` decodes to a NUL, Swift passes a
    /// String to `inet_pton` as a C string, and the measurement then stops before the part of the
    /// host that names somebody else.
    func testEvaluate_whenHostIsSpelledIndirectly_denies() {
        check([
            Case(
                "NUL truncates the address",
                origin: "http://127.0.0.1%00.evil.example:8080",
                host: "127.0.0.1%00.evil.example:8080",
                .deny(.hostNotAddressLiteral("127.0.0.1%00.evil.example:8080"))
            ),
            Case(
                "percent-encoded address",
                origin: "http://%31%32%37%2e%30%2e%30%2e%31:8080",
                host: "%31%32%37%2e%30%2e%30%2e%31:8080",
                .deny(.hostNotAddressLiteral("%31%32%37%2e%30%2e%30%2e%31:8080"))
            ),
            Case(
                "fullwidth letters fold to ASCII",
                origin: "http://Ｌｏcalhost:8080",
                host: "Ｌｏcalhost:8080",
                .deny(.hostNotAddressLiteral("Ｌｏcalhost:8080"))
            ),
            Case(
                "ideographic full stop folds to a dot",
                origin: "http://127。0。0。1:8080",
                host: "127。0。0。1:8080",
                .deny(.hostNotAddressLiteral("127。0。0。1:8080"))
            ),
            Case(
                "port outside what a socket can carry",
                origin: "http://127.0.0.1:99999999999",
                host: "127.0.0.1:99999999999",
                .deny(.hostNotAddressLiteral("127.0.0.1:99999999999"))
            )
        ])
    }

    /// A userinfo section puts the real host after an `@`, where a reader skimming the start of
    /// the value will not look. `URLComponents` does split it out correctly, so this pins that
    /// the split is noticed rather than parsed past.
    func testEvaluate_whenHostCarriesUserinfo_denies() {
        check([
            Case(
                "address as the username",
                origin: "http://127.0.0.1:8080",
                host: "127.0.0.1:8080@evil.example",
                .deny(.hostNotAddressLiteral("127.0.0.1:8080@evil.example"))
            ),
            Case(
                "empty userinfo",
                origin: "http://127.0.0.1:8080",
                host: "@127.0.0.1:8080",
                .deny(.hostNotAddressLiteral("@127.0.0.1:8080"))
            )
        ])
    }

    /// An `Origin` is an authority and nothing else, so a path, query or fragment on one means it
    /// is not the header a browser writes — and each of those is somewhere an attacker's host can
    /// be parked in the hope the comparison reads far enough to find it.
    func testEvaluate_whenOriginCarriesMoreThanAnAuthority_denies() {
        check([
            Case(
                "fragment",
                origin: "http://127.0.0.1:8080#@evil.example",
                host: "127.0.0.1:8080",
                .deny(.originNotWebScheme("http://127.0.0.1:8080#@evil.example"))
            ),
            Case(
                "query",
                origin: "http://127.0.0.1:8080?x=@evil.example",
                host: "127.0.0.1:8080",
                .deny(.originNotWebScheme("http://127.0.0.1:8080?x=@evil.example"))
            ),
            Case(
                "path",
                origin: "http://127.0.0.1:8080/",
                host: "127.0.0.1:8080",
                .deny(.originNotWebScheme("http://127.0.0.1:8080/"))
            )
        ])
    }

    // MARK: - Denied: cross-origin

    /// A WebSocket handshake is not subject to the same-origin policy: any page in the browser may
    /// open one to any address it likes. It cannot forge `Origin`, so that header is what
    /// distinguishes our own page from someone else's.
    func testEvaluate_whenOriginIsAnotherSite_denies() {
        check([
            Case(
                "attacker page, our address",
                origin: "http://evil.example",
                host: "127.0.0.1:8080",
                .deny(.originMismatch(origin: "evil.example:80", host: "127.0.0.1:8080"))
            ),
            Case(
                "different port on the same host",
                origin: "http://127.0.0.1:9999",
                host: "127.0.0.1:8080",
                .deny(.originMismatch(origin: "127.0.0.1:9999", host: "127.0.0.1:8080"))
            ),
            Case(
                "loopback is not localhost's twin",
                origin: "http://127.0.0.1:8080",
                host: "localhost:8080",
                .deny(.originMismatch(origin: "127.0.0.1:8080", host: "localhost:8080"))
            )
        ])
    }

    // MARK: - Denied: not a browser

    /// Every browser sends `Origin` on a WebSocket handshake, so a handshake without one did not
    /// come from a browser — and anything that is not a browser is free to send whatever `Origin`
    /// it likes. Accepting the absent header would therefore hand an attacker on the network the
    /// one bypass that makes the rest of this check pointless.
    func testEvaluate_whenOriginIsAbsent_denies() {
        check([
            Case("absent", origin: nil, host: "127.0.0.1:8080", .deny(.missingOrigin)),
            Case("empty", origin: "", host: "127.0.0.1:8080", .deny(.missingOrigin)),
            Case("whitespace", origin: "   ", host: "127.0.0.1:8080", .deny(.missingOrigin))
        ])
    }

    /// `Origin: null` is what a browser sends from a sandboxed iframe, a `data:` document or a
    /// page opened from the filesystem. None of those is our own page, and `null` is shared by all
    /// of them, so it can never be matched against an authority.
    func testEvaluate_whenOriginIsOpaqueOrNonWeb_denies() {
        check([
            Case("null", origin: "null", host: "127.0.0.1:8080", .deny(.originNotWebScheme("null"))),
            Case("file", origin: "file://", host: "127.0.0.1:8080", .deny(.originNotWebScheme("file://"))),
            Case(
                "custom scheme",
                origin: "chrome-extension://abcdef",
                host: "127.0.0.1:8080",
                .deny(.originNotWebScheme("chrome-extension://abcdef"))
            ),
            Case(
                "not a URL at all",
                origin: "%%%",
                host: "127.0.0.1:8080",
                .deny(.originNotWebScheme("%%%"))
            )
        ])
    }

    /// HTTP/1.1 requires `Host`, so its absence is a malformed request rather than an attack —
    /// but it is still the header the rest of the decision rests on, so it cannot be defaulted.
    func testEvaluate_whenHostIsAbsent_denies() {
        check([
            Case("absent", origin: "http://127.0.0.1:8080", host: nil, .deny(.missingHost)),
            Case("empty", origin: "http://127.0.0.1:8080", host: "", .deny(.missingHost)),
            Case("port only", origin: "http://127.0.0.1:8080", host: ":8080", .deny(.missingHost))
        ])
    }

    // MARK: - Reporting

    /// The headers are attacker-controlled and the reason is written to the developer's terminal,
    /// so a rejection must not be able to smuggle control characters into it or flood it — the
    /// same treatment `EditorLauncher` gives environment values it quotes back.
    func testReason_whenAHeaderCarriesControlCharacters_stripsThem() {
        let forged = "evil.example\n⚠️ Listening on all interfaces"
        let decision = guardUnderTest.evaluate(origin: "http://127.0.0.1:8080", host: "\(forged):8080")
        guard case .deny(let rejection) = decision else {
            return XCTFail("expected a rejection, got \(decision)")
        }

        let reason = rejection.reason
        XCTAssertFalse(reason.contains("\n"), "a newline would let the header forge a second log line")
        XCTAssertTrue(reason.contains("evil.example"), "the reason should still name what was rejected")
    }

    /// The set of things that can break a line, or move a cursor, is wider than `\n`.
    func testReason_whenAHeaderCarriesEscapesOrLineSeparators_stripsThem() {
        let hostile = "evil\u{1B}[2J\u{07}.example\u{2028}forged\u{2029}again\u{0085}too"
        let decision = guardUnderTest.evaluate(origin: "http://127.0.0.1:8080", host: "\(hostile):8080")
        guard case .deny(let rejection) = decision else {
            return XCTFail("expected a rejection, got \(decision)")
        }

        let reason = rejection.reason
        for scalar in ["\u{1B}", "\u{07}", "\u{2028}", "\u{2029}", "\u{0085}"] {
            XCTAssertFalse(reason.contains(scalar), "\(scalar.unicodeScalars.first!) survived")
        }
    }

    func testReason_whenAHeaderIsOverlong_truncatesIt() {
        let long = String(repeating: "a", count: 500) + ".example"
        let decision = guardUnderTest.evaluate(origin: "http://127.0.0.1:8080", host: "\(long):8080")
        guard case .deny(let rejection) = decision else {
            return XCTFail("expected a rejection, got \(decision)")
        }

        XCTAssertLessThan(rejection.reason.utf8.count, 400, "an overlong header must not flood the terminal")
    }

    /// Counted in characters, a base letter followed by a thousand combining marks is one
    /// character, so a cap on characters would let the whole run through.
    func testReason_whenAHeaderIsOneEnormousCharacter_stillTruncates() {
        let bomb = "a" + String(repeating: "\u{0301}", count: 1000) + ".example"
        let decision = guardUnderTest.evaluate(origin: "http://127.0.0.1:8080", host: "\(bomb):8080")
        guard case .deny(let rejection) = decision else {
            return XCTFail("expected a rejection, got \(decision)")
        }

        XCTAssertLessThan(rejection.reason.utf8.count, 400, "a grapheme cluster is not a length limit")
    }

    /// Whatever the reason, it has to tell the developer what to do about it — these rejections
    /// surface as a browser tab that silently stops live-reloading.
    func testReason_forEveryRejection_isNotEmpty() {
        let rejections: [WebSocketOriginGuard.Rejection] = [
            .missingHost,
            .missingOrigin,
            .hostNotAddressLiteral("evil.example"),
            .originNotWebScheme("null"),
            .originMismatch(origin: "evil.example:80", host: "127.0.0.1:8080")
        ]
        for rejection in rejections {
            XCTAssertFalse(rejection.reason.isEmpty, "\(rejection) has no reason text")
        }
    }
}

import XCTest
@testable import HirundoCore

final class ListenAddressTests: XCTestCase {

    // MARK: - Resolution table

    func testResolve_whenHostIsLocalhostLowercase_resolvesToIPv4Loopback() throws {
        let resolved = try resolveListenAddress(host: "localhost")

        XCTAssertEqual(resolved.address, "127.0.0.1")
        XCTAssertTrue(resolved.forceIPv4)
        XCTAssertFalse(resolved.isWildcard)
    }

    func testResolve_whenHostIsLocalhostMixedCase_resolvesToIPv4Loopback() throws {
        let resolved = try resolveListenAddress(host: "LocalHost")

        XCTAssertEqual(resolved.address, "127.0.0.1")
        XCTAssertTrue(resolved.forceIPv4)
        XCTAssertFalse(resolved.isWildcard)
    }

    func testResolve_whenHostIsIPv4Loopback_resolvesAsIs() throws {
        let resolved = try resolveListenAddress(host: "127.0.0.1")

        XCTAssertEqual(resolved.address, "127.0.0.1")
        XCTAssertTrue(resolved.forceIPv4)
        XCTAssertFalse(resolved.isWildcard)
    }

    func testResolve_whenHostIsIPv4Any_isWildcard() throws {
        let resolved = try resolveListenAddress(host: "0.0.0.0")

        XCTAssertEqual(resolved.address, "0.0.0.0")
        XCTAssertTrue(resolved.forceIPv4)
        XCTAssertTrue(resolved.isWildcard)
    }

    func testResolve_whenHostIsIPv6Loopback_resolvesAsIs() throws {
        let resolved = try resolveListenAddress(host: "::1")

        XCTAssertEqual(resolved.address, "::1")
        XCTAssertFalse(resolved.forceIPv4)
        XCTAssertFalse(resolved.isWildcard)
    }

    func testResolve_whenHostIsIPv6Any_isWildcard() throws {
        let resolved = try resolveListenAddress(host: "::")

        XCTAssertEqual(resolved.address, "::")
        XCTAssertFalse(resolved.forceIPv4)
        XCTAssertTrue(resolved.isWildcard)
    }

    func testResolve_whenHostIsFullyExpandedIPv6Any_isWildcard() throws {
        // Same as "::" but written out fully -- isWildcard must come from the parsed bytes,
        // not from a string comparison against "::".
        let resolved = try resolveListenAddress(host: "0000:0000:0000:0000:0000:0000:0000:0000")

        XCTAssertTrue(resolved.isWildcard)
    }

    func testResolve_whenHostIsOtherIPv4Literal_resolvesAsIs() throws {
        let resolved = try resolveListenAddress(host: "192.168.1.10")

        XCTAssertEqual(resolved.address, "192.168.1.10")
        XCTAssertTrue(resolved.forceIPv4)
        XCTAssertFalse(resolved.isWildcard)
    }

    func testResolve_whenHostIsOtherIPv6Literal_resolvesAsIs() throws {
        let resolved = try resolveListenAddress(host: "fe80::1")

        XCTAssertEqual(resolved.address, "fe80::1")
        XCTAssertFalse(resolved.forceIPv4)
        XCTAssertFalse(resolved.isWildcard)
    }

    func testResolve_whenHostIsAHostName_throwsNotNumeric() {
        XCTAssertThrowsError(try resolveListenAddress(host: "example.com")) { error in
            XCTAssertEqual(error as? ListenAddressError, .notNumeric("example.com"))
        }
    }

    func testResolve_whenHostIsAHyphenatedHostName_throwsNotNumeric() {
        XCTAssertThrowsError(try resolveListenAddress(host: "my-host")) { error in
            XCTAssertEqual(error as? ListenAddressError, .notNumeric("my-host"))
        }
    }

    func testResolve_whenHostIsEmptyString_throwsNotNumeric() {
        XCTAssertThrowsError(try resolveListenAddress(host: "")) { error in
            XCTAssertTrue(error is ListenAddressError)
        }
    }

    func testResolve_whenHostIsWhitespaceOnly_throwsNotNumeric() {
        XCTAssertThrowsError(try resolveListenAddress(host: "   ")) { error in
            XCTAssertTrue(error is ListenAddressError)
        }
    }

    // MARK: - Trimming

    func testResolve_whenHostHasSurroundingWhitespace_isTrimmedBeforeResolution() throws {
        let resolved = try resolveListenAddress(host: "  localhost  ")

        XCTAssertEqual(resolved.address, "127.0.0.1")
    }

    // MARK: - displayHost

    func testDisplayHost_whenIPv6_isBracketed() throws {
        let resolved = try resolveListenAddress(host: "::1")

        XCTAssertEqual(resolved.displayHost, "[::1]")
    }

    func testDisplayHost_whenIPv4_isNotBracketed() throws {
        let resolved = try resolveListenAddress(host: "127.0.0.1")

        XCTAssertEqual(resolved.displayHost, "127.0.0.1")
    }

    // MARK: - Error message

    func testNotNumericError_hasGuidingDescription() {
        let error = ListenAddressError.notNumeric("example.com")

        XCTAssertEqual(
            error.errorDescription,
            "Server host must be a numeric IP address, not a host name: 'example.com'. Use 127.0.0.1 for local access or 0.0.0.0 to accept connections from other machines."
        )
    }
}

import XCTest
@testable import HirundoCore

final class ServeOptionsTests: XCTestCase {

    func testResolve_whenCLIOmitsEverything_usesNonDefaultConfigValues() throws {
        let cli = ServeCommandLineOptions(port: nil, noReload: false)
        let config = Server(port: 3000, liveReload: false)

        let resolved = try resolveServeOptions(cli: cli, config: config)

        XCTAssertEqual(resolved.port, 3000)
        XCTAssertFalse(resolved.liveReload)
    }

    func testResolve_whenCLIOmitsEverything_usesDefaultConfigValues() throws {
        let cli = ServeCommandLineOptions(port: nil, noReload: false)
        let config = Server()

        let resolved = try resolveServeOptions(cli: cli, config: config)

        XCTAssertEqual(resolved.port, 8080)
        XCTAssertTrue(resolved.liveReload)
    }

    func testResolve_whenCLISpecifiesPort_CLIPortWins() throws {
        let cli = ServeCommandLineOptions(port: 9000, noReload: false)
        let config = Server(port: 3000, liveReload: true)

        let resolved = try resolveServeOptions(cli: cli, config: config)

        XCTAssertEqual(resolved.port, 9000)
    }

    func testResolve_whenCLISpecifiesNoReload_CLIDisablesLiveReloadEvenIfConfigEnablesIt() throws {
        let cli = ServeCommandLineOptions(port: nil, noReload: true)
        let config = Server(liveReload: true)

        let resolved = try resolveServeOptions(cli: cli, config: config)

        XCTAssertFalse(resolved.liveReload)
    }

    func testResolve_whenCLIDoesNotSpecifyNoReload_configLiveReloadFalseIsRespected() throws {
        let cli = ServeCommandLineOptions(port: nil, noReload: false)
        let config = Server(liveReload: false)

        let resolved = try resolveServeOptions(cli: cli, config: config)

        XCTAssertFalse(resolved.liveReload)
    }

    func testResolve_whenCLISpecifiesBothPortAndNoReload_bothCLIValuesWin() throws {
        let cli = ServeCommandLineOptions(port: 9000, noReload: true)
        let config = Server(port: 3000, liveReload: true)

        let resolved = try resolveServeOptions(cli: cli, config: config)

        XCTAssertEqual(resolved.port, 9000)
        XCTAssertFalse(resolved.liveReload)
    }

    // MARK: - Port Range

    func testResolve_whenConfigPortIsAboveTheMaximum_throwsPortOutOfRange() {
        // `UInt16(port)` in DevelopmentServer.start() traps on this value, so it must never
        // get that far. Before live reload, config.server.port was parsed and never read, which
        // is why a config this broken could exist in the wild already.
        let cli = ServeCommandLineOptions(port: nil, noReload: false)
        let config = Server(port: 99999, liveReload: true)

        XCTAssertThrowsError(try resolveServeOptions(cli: cli, config: config)) { error in
            XCTAssertEqual(error as? ServeOptionsError, .portOutOfRange(99999))
        }
    }

    func testResolve_whenCLIPortIsAboveTheMaximum_throwsPortOutOfRange() {
        let cli = ServeCommandLineOptions(port: 65536, noReload: false)
        let config = Server(port: 8080, liveReload: true)

        XCTAssertThrowsError(try resolveServeOptions(cli: cli, config: config)) { error in
            XCTAssertEqual(error as? ServeOptionsError, .portOutOfRange(65536))
        }
    }

    func testResolve_whenCLIPortIsNegative_throwsPortOutOfRange() {
        let cli = ServeCommandLineOptions(port: -1, noReload: false)
        let config = Server()

        XCTAssertThrowsError(try resolveServeOptions(cli: cli, config: config)) { error in
            XCTAssertEqual(error as? ServeOptionsError, .portOutOfRange(-1))
        }
    }

    func testResolve_whenPortIsZero_throwsPortOutOfRange() {
        // The socket layer would accept 0 as "any free port", but nothing reads the assigned
        // port back, so the URL serve prints and opens would say `:0`.
        let cli = ServeCommandLineOptions(port: 0, noReload: false)
        let config = Server()

        XCTAssertThrowsError(try resolveServeOptions(cli: cli, config: config)) { error in
            XCTAssertEqual(error as? ServeOptionsError, .portOutOfRange(0))
        }
    }

    func testResolve_whenPortIsAtEitherEndOfTheValidRange_resolvesIt() throws {
        let lowest = try resolveServeOptions(
            cli: ServeCommandLineOptions(port: 1, noReload: false),
            config: Server()
        )
        let highest = try resolveServeOptions(
            cli: ServeCommandLineOptions(port: 65535, noReload: false),
            config: Server()
        )

        XCTAssertEqual(lowest.port, 1)
        XCTAssertEqual(highest.port, 65535)
    }

    func testResolve_whenCLIPortIsValidAndConfigPortIsNot_theCLIPortIsUsed() throws {
        // The invalid config value is never reached, so `--port` remains a way out of a broken
        // config.yaml rather than a second thing to fix.
        let cli = ServeCommandLineOptions(port: 8080, noReload: false)
        let config = Server(port: 99999, liveReload: true)

        let resolved = try resolveServeOptions(cli: cli, config: config)

        XCTAssertEqual(resolved.port, 8080)
    }

    func testErrorDescription_whenPortIsOutOfRange_namesTheValueAndTheRange() {
        let message = ServeOptionsError.portOutOfRange(99999).errorDescription ?? ""

        XCTAssertTrue(message.contains("99999"), message)
        XCTAssertTrue(message.contains("between 1 and 65535"), message)
    }

    func testErrorDescription_whenPortIsZero_explainsWhyAnyFreePortIsRefused() {
        let message = ServeOptionsError.portOutOfRange(0).errorDescription ?? ""

        XCTAssertTrue(message.contains("any free port"), message)
    }
}

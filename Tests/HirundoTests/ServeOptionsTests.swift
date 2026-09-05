import XCTest
@testable import HirundoCore

final class ServeOptionsTests: XCTestCase {

    func testResolve_whenCLIOmitsEverything_usesNonDefaultConfigValues() {
        let cli = ServeCommandLineOptions(port: nil, noReload: false)
        let config = Server(port: 3000, liveReload: false)

        let resolved = resolveServeOptions(cli: cli, config: config)

        XCTAssertEqual(resolved.port, 3000)
        XCTAssertFalse(resolved.liveReload)
    }

    func testResolve_whenCLIOmitsEverything_usesDefaultConfigValues() {
        let cli = ServeCommandLineOptions(port: nil, noReload: false)
        let config = Server()

        let resolved = resolveServeOptions(cli: cli, config: config)

        XCTAssertEqual(resolved.port, 8080)
        XCTAssertTrue(resolved.liveReload)
    }

    func testResolve_whenCLISpecifiesPort_CLIPortWins() {
        let cli = ServeCommandLineOptions(port: 9000, noReload: false)
        let config = Server(port: 3000, liveReload: true)

        let resolved = resolveServeOptions(cli: cli, config: config)

        XCTAssertEqual(resolved.port, 9000)
    }

    func testResolve_whenCLISpecifiesNoReload_CLIDisablesLiveReloadEvenIfConfigEnablesIt() {
        let cli = ServeCommandLineOptions(port: nil, noReload: true)
        let config = Server(liveReload: true)

        let resolved = resolveServeOptions(cli: cli, config: config)

        XCTAssertFalse(resolved.liveReload)
    }

    func testResolve_whenCLIDoesNotSpecifyNoReload_configLiveReloadFalseIsRespected() {
        let cli = ServeCommandLineOptions(port: nil, noReload: false)
        let config = Server(liveReload: false)

        let resolved = resolveServeOptions(cli: cli, config: config)

        XCTAssertFalse(resolved.liveReload)
    }

    func testResolve_whenCLISpecifiesBothPortAndNoReload_bothCLIValuesWin() {
        let cli = ServeCommandLineOptions(port: 9000, noReload: true)
        let config = Server(port: 3000, liveReload: true)

        let resolved = resolveServeOptions(cli: cli, config: config)

        XCTAssertEqual(resolved.port, 9000)
        XCTAssertFalse(resolved.liveReload)
    }
}

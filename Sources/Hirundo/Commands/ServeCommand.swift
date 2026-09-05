import ArgumentParser
import HirundoCore
import Foundation
#if os(macOS)
import AppKit
#endif

/// Resumes a `CheckedContinuation` at most once.
///
/// Two signal sources are armed (SIGINT and SIGTERM) and both can fire — a terminal sending
/// SIGINT while a supervisor sends SIGTERM is exactly the shutdown a development server sees.
/// Resuming a `CheckedContinuation` twice traps the process, so the second event has to find
/// the continuation already gone. `NSLock` rather than an actor because a signal source's event
/// handler is a synchronous callback on a `DispatchQueue` and cannot await anything.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func fire() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}

/// Suspends until the process receives SIGINT or SIGTERM.
///
/// `withTaskCancellationHandler` is not an option here: a signal never cancels a Swift task, so
/// the handler never runs and the process dies before anything is stopped. A `DispatchSource`
/// signal source does observe the signal, but only once the default disposition — which
/// terminates the process outright — has been replaced by `SIG_IGN`. That disposition is
/// process-global state, so it is installed here and restored on the way out.
private func waitForShutdownSignal() async {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    defer {
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)
    }

    let queue = DispatchQueue(label: "com.hirundo.serve.signal")
    let sources = [SIGINT, SIGTERM].map { DispatchSource.makeSignalSource(signal: $0, queue: queue) }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let gate = ResumeOnce(continuation)
        for source in sources {
            source.setEventHandler { gate.fire() }
            source.resume()
        }
    }
    for source in sources {
        source.cancel()
    }
}

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start development server with live reload"
    )

    @Option(name: .long, help: "Server port (defaults to server.port in config.yaml)")
    var port: Int?

    @Option(name: .long, help: "Numeric address to bind to. Use 0.0.0.0 to accept connections from other machines")
    var host: String = "localhost"

    @Flag(name: .long, help: "Disable live reload")
    var noReload: Bool = false

    @Flag(name: .long, help: "Don't open browser")
    var noBrowser: Bool = false

    @Flag(name: .long, help: "Include draft posts")
    var drafts: Bool = false

    @Flag(name: .long, help: "Show verbose error information")
    var verbose: Bool = false

    mutating func run() async throws {
        // `run()` is `mutating` on a struct, so `self` must not be captured by any escaping
        // closure below. Everything the rebuild plumbing needs is copied into a local constant
        // here and only those constants are used from that point on.
        let verbose = self.verbose
        let includeDrafts = self.drafts
        let cliOptions = ServeCommandLineOptions(port: self.port, noReload: self.noReload)
        let hostArgument = self.host
        let shouldOpenBrowser = !self.noBrowser

        let currentDirectory = FileManager.default.currentDirectoryPath

        print("🌐 Starting development server…")

        var server: DevelopmentServer?
        var watcher: HotReloadManager?
        do {
            // `serve` always reads `config.yaml` from the working directory: the output
            // directory, the watched directories and the port all come from it.
            let configURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent("config.yaml")
            let config = try HirundoConfig.load(from: configURL)

            let options = try resolveServeOptions(cli: cliOptions, config: config.server)
            let listen = try resolveListenAddress(host: hostArgument)

            print("🏠 Host: \(listen.displayHost)")
            print("🔌 Port: \(options.port)")
            print("🔄 Live reload: \(options.liveReload ? "enabled" : "disabled")")
            print("🌍 Open browser: \(shouldOpenBrowser ? "yes" : "no")")
            print("📝 Drafts: \(includeDrafts ? "included" : "excluded")")

            if listen.isWildcard {
                print("⚠️  Listening on all interfaces. The live reload WebSocket has no authentication — do not use this on an untrusted network.")
            }

            let projectRoot = URL(fileURLWithPath: currentDirectory)
            let outputPath = projectRoot.appendingPathComponent(config.build.outputDirectory).path
            let watchCandidates = [
                config.build.contentDirectory,
                config.build.templatesDirectory,
                config.build.staticDirectory
            ].map { projectRoot.appendingPathComponent($0).path }

            // A configuration that puts the output inside a watched directory makes every
            // rebuild trigger the next one, forever. Refuse before doing any work rather than
            // letting the user discover it as a pegged core. Only live reload watches anything,
            // so a layout like this is still usable with `--no-reload`.
            if options.liveReload {
                try validateWatchPaths(watchCandidates, outputPath: outputPath)
            }

            // Step 1: build once so that the very first request has something to serve. A
            // failure here is reported but not fatal — a running server showing a stale or
            // partial site is far easier to debug than a command that refused to start.
            print("🔨 Running initial build…")
            do {
                let generator = try SiteGenerator(projectPath: currentDirectory, config: config)
                let result = try await generator.buildWithRecovery(
                    clean: false,
                    includeDrafts: includeDrafts,
                    environment: "development"
                )
                if result.success {
                    print("✅ Initial build finished (\(result.successCount) file(s))")
                } else {
                    eprint("❌ Initial build completed with errors. Success: \(result.successCount), Failed: \(result.failCount)")
                    for detail in result.errors.prefix(10) {
                        eprint("- [\(detail.stage)] \(detail.file): \(detail.error)")
                    }
                    eprint("⚠️  Starting the server anyway — fix the errors above and save to rebuild.")
                }
            } catch {
                eprint("❌ Initial build failed: \(error.localizedDescription)")
                eprint("⚠️  Starting the server anyway — fix the errors above and save to rebuild.")
            }

            // Step 2: the hub the HTTP server registers live reload clients with, and that the
            // rebuild coordinator broadcasts through.
            let hub = LiveReloadHub()
            let developmentServer = DevelopmentServer(
                projectPath: currentDirectory,
                port: options.port,
                host: listen.address,
                liveReload: options.liveReload,
                fileManager: .default,
                outputDirectory: config.build.outputDirectory,
                hub: hub
            )
            server = developmentServer

            // Step 3: serialize rebuilds. A fresh `SiteGenerator` per rebuild is required, not a
            // concession: a generator owns a `TemplateCache` that only expires entries on a
            // one-hour timer and has no file-change invalidation, so reusing one across rebuilds
            // would keep serving the template the user just edited for up to an hour — precisely
            // the staleness live reload exists to eliminate. Constructing it inside the closure
            // also happens to satisfy `@Sendable`, since `SiteGenerator` is a non-`Sendable`
            // class and only the project path and the (`Sendable`) configuration are captured.
            let coordinator = RebuildCoordinator(
                build: {
                    let generator = try SiteGenerator(projectPath: currentDirectory, config: config)
                    return try await generator.buildWithRecovery(
                        clean: false,
                        includeDrafts: includeDrafts,
                        environment: "development"
                    )
                },
                onSuccess: {
                    print("🔄 Rebuilt — reloading connected browsers")
                    await hub.broadcast("reload")
                },
                onFailure: { error in
                    eprint("❌ Rebuild failed: \(error.localizedDescription)")
                }
            )

            // Step 4: watch the source directories. The output directory is deliberately absent
            // from `watchPaths` — watching what the build writes is an endless rebuild loop —
            // and is named in `ignorePatterns` as well, because the built-in defaults only know
            // the literal name `_site` and this project may have configured another one.
            if options.liveReload {
                let watchPaths = watchCandidates.filter { path in
                    var isDirectory: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                    return exists && isDirectory.boolValue
                }

                if watchPaths.isEmpty {
                    // `HotReloadManager.start()` fails on a path it cannot open, so an empty set
                    // is reported rather than passed on.
                    print("⚠️  No content, template or static directory found — file watching is off.")
                } else {
                    let manager = HotReloadManager(
                        watchPaths: watchPaths,
                        ignorePatterns: [config.build.outputDirectory],
                        symlinkBoundary: .project(
                            root: currentDirectory,
                            excludingDirectoriesNamed: [config.build.outputDirectory]
                        ),
                        callback: { _ in
                            Task { await coordinator.requestRebuild() }
                        }
                    )
                    // Recorded before `start()` so that a start which throws part-way through
                    // is still stopped by the catch clause below.
                    watcher = manager
                    try await manager.start()
                    print("👀 Watching \(watchPaths.count) director\(watchPaths.count == 1 ? "y" : "ies") for changes")
                }
            }

            // Step 5: serve.
            try await developmentServer.start()
            let url = "http://\(listen.displayHost):\(options.port)"
            print("✅ Development server is running at \(url)")

            #if os(macOS)
            if shouldOpenBrowser, let browserURL = URL(string: url) {
                _ = NSWorkspace.shared.open(browserURL)
            }
            #endif

            print("🔚 Press Ctrl+C to stop")
            await waitForShutdownSignal()

            // Shut down in the order that cannot lose work: stop accepting requests, stop
            // queueing new rebuilds, then let whatever is already building finish.
            print("⏹️  Stopping server…")
            await developmentServer.stop()
            await watcher?.stop()
            await coordinator.waitForQuiescence()
            print("🛑 Server stopped")
        } catch {
            // Ensure the server and the watcher are stopped even when startup failed midway.
            await server?.stop()
            await watcher?.stop()
            handleError(error, context: "Serve", verbose: verbose)
            throw ExitCode.failure
        }
    }
}

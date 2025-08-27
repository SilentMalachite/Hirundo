import ArgumentParser
import HirundoCore
import Foundation
#if os(macOS)
import AppKit
#endif

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
@main
struct HirundoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hirundo",
        abstract: "A modern, fast, and secure static site generator built with Swift",
        version: "1.0.3",
        subcommands: [
            InitCommand.self,
            BuildCommand.self,
            ServeCommand.self,
            NewCommand.self,
            CleanCommand.self
        ]
    )
}

import ArgumentParser
import HirundoCore
import Foundation
#if os(macOS)
import AppKit
#endif

struct HirundoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hirundo",
        abstract: "A modern, fast, and secure static site generator built with Swift",
        version: "1.0.2",
        subcommands: [
            InitCommand.self,
            BuildCommand.self,
            ServeCommand.self,
            NewCommand.self,
            CleanCommand.self
        ]
    )
}

HirundoCommand.main()
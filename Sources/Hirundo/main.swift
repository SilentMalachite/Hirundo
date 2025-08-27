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

struct BuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the static site"
    )
    
    @Option(name: .long, help: "Configuration file path")
    var config: String = "config.yaml"
    
    @Option(name: .long, help: "Build environment (development/production)")
    var environment: String = "production"
    
    @Flag(name: .long, help: "Include draft posts")
    var drafts: Bool = false
    
    @Flag(name: .long, help: "Clean output before building")
    var clean: Bool = false
    
    @Flag(name: .long, help: "Continue building even if some files fail (error recovery mode)")
    var continueOnError: Bool = false
    
    mutating func run() throws {
        print("🔨 BUILD COMMAND IS RUNNING!")
        print("✅ ParsableCommand is working!")
        print("📁 Config: \(config)")
        print("🏗️ Environment: \(environment)")
        print("📄 Include drafts: \(drafts)")
        print("🧹 Clean: \(clean)")
        
        // For now, just test that the command works
        let currentDirectory = FileManager.default.currentDirectoryPath
        print("📁 Current directory: \(currentDirectory)")
        
        // Test SiteGenerator initialization
        do {
            print("🔧 Initializing SiteGenerator...")
            let generator = try SiteGenerator(projectPath: currentDirectory)
            print("✅ SiteGenerator initialized successfully!")
        } catch {
            print("❌ Failed to initialize SiteGenerator:")
            print("Error: \(error)")
            handleError(error, context: "SiteGenerator initialization")
            throw ExitCode.failure
        }
    }
}

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a new Hirundo site"
    )
    
    @Argument(help: "Path where the new site will be created")
    var path: String = "."
    
    @Option(name: .long, help: "Site title")
    var title: String = "My Hirundo Site"
    
    @Flag(name: .long, help: "Include blog functionality")
    var blog: Bool = false
    
    @Flag(name: .long, help: "Force creation in non-empty directory")
    var force: Bool = false
    
    mutating func run() throws {
        print("🚀 Creating new Hirundo site at: \(path)")
        print("📝 Title: \(title)")
        print("📚 Blog functionality: \(blog ? "enabled" : "disabled")")
        print("💪 Force mode: \(force ? "enabled" : "disabled")")
        
        let fileManager = FileManager.default
        let siteURL = URL(fileURLWithPath: path)
        
        // Check if directory exists and is not empty
        if fileManager.fileExists(atPath: path) {
            do {
                let contents = try fileManager.contentsOfDirectory(at: siteURL, includingPropertiesForKeys: nil)
                if !contents.isEmpty && !force {
                    print("❌ Directory is not empty. Use --force to override.")
                    throw ExitCode.failure
                }
            } catch {
                print("❌ Failed to check directory contents: \(error)")
                throw ExitCode.failure
            }
        }
        
        print("✅ Init command executed successfully!")
        print("💡 Full implementation would create directory structure and files")
    }
}

struct ServeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start development server with live reload"
    )
    
    @Option(name: .long, help: "Server port")
    var port: Int = 8080
    
    @Option(name: .long, help: "Server host")
    var host: String = "localhost"
    
    @Flag(name: .long, help: "Disable live reload")
    var noReload: Bool = false
    
    @Flag(name: .long, help: "Don't open browser")
    var noBrowser: Bool = false
    
    mutating func run() throws {
        print("🌐 Starting development server...")
        print("🏠 Host: \(host)")
        print("🔌 Port: \(port)")
        print("🔄 Live reload: \(!noReload ? "enabled" : "disabled")")
        print("🌍 Open browser: \(!noBrowser ? "yes" : "no")")
        
        let currentDirectory = FileManager.default.currentDirectoryPath
        
        // Test SiteGenerator initialization
        do {
            print("🔧 Initializing SiteGenerator...")
            let generator = try SiteGenerator(projectPath: currentDirectory)
            print("✅ SiteGenerator initialized successfully!")
        } catch {
            print("❌ Failed to initialize SiteGenerator:")
            print("Error: \(error)")
            handleError(error, context: "SiteGenerator initialization")
            throw ExitCode.failure
        }
        
        print("✅ Serve command executed successfully!")
        print("💡 Full implementation would start DevelopmentServer")
    }
}

struct NewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create new content",
        subcommands: [
            NewPostCommand.self,
            NewPageCommand.self
        ]
    )
}

struct NewPostCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "post",
        abstract: "Create a new blog post"
    )
    
    @Argument(help: "Post title")
    var title: String
    
    @Option(name: .long, help: "URL slug")
    var slug: String?
    
    @Option(name: .long, help: "Comma-separated categories")
    var categories: String?
    
    @Option(name: .long, help: "Comma-separated tags")
    var tags: String?
    
    @Flag(name: .long, help: "Create as draft")
    var draft: Bool = false
    
    @Flag(name: .long, help: "Open in editor")
    var open: Bool = false
    
    mutating func run() throws {
        print("📝 Creating new blog post...")
        print("📄 Title: \(title)")
        print("🏷️ Slug: \(slug ?? "auto-generated")")
        print("📂 Categories: \(categories ?? "none")")
        print("🏷️ Tags: \(tags ?? "none")")
        print("📝 Draft: \(draft ? "yes" : "no")")
        print("🖊️ Open in editor: \(open ? "yes" : "no")")
        
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let postsURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent("content/posts")
        
        // Ensure posts directory exists
        do {
            try fileManager.createDirectory(at: postsURL, withIntermediateDirectories: true)
            print("✅ Posts directory ready: \(postsURL.path)")
        } catch {
            print("❌ Failed to create posts directory: \(error)")
            throw ExitCode.failure
        }
        
        print("✅ New post command executed successfully!")
        print("💡 Full implementation would create the post file")
    }
}

struct NewPageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "page",
        abstract: "Create a new page"
    )
    
    @Argument(help: "Page title")
    var title: String
    
    @Option(name: .long, help: "Page path")
    var path: String?
    
    @Option(name: .long, help: "Template layout")
    var layout: String = "default"
    
    @Flag(name: .long, help: "Open in editor")
    var open: Bool = false
    
    mutating func run() throws {
        print("📄 Creating new page...")
        print("📝 Title: \(title)")
        print("📁 Path: \(path ?? "auto-generated")")
        print("🎨 Layout: \(layout)")
        print("🖊️ Open in editor: \(open ? "yes" : "no")")
        
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let contentURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent("content")
        
        // Ensure content directory exists
        do {
            try fileManager.createDirectory(at: contentURL, withIntermediateDirectories: true)
            print("✅ Content directory ready: \(contentURL.path)")
        } catch {
            print("❌ Failed to create content directory: \(error)")
            throw ExitCode.failure
        }
        
        print("✅ New page command executed successfully!")
        print("💡 Full implementation would create the page file")
    }
}

struct CleanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Clean output directory and caches"
    )
    
    @Flag(name: .long, help: "Also clean asset cache")
    var cache: Bool = false
    
    @Flag(name: .long, help: "Skip confirmation")
    var force: Bool = false
    
    mutating func run() throws {
        print("🧹 Cleaning...")
        print("🗂️ Clean cache: \(cache ? "yes" : "no")")
        print("💪 Force mode: \(force ? "yes" : "no")")
        
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let outputURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent("_site")
        let cacheURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent(".hirundo-cache")
        
        if !force {
            print("⚠️  This would delete:")
            if fileManager.fileExists(atPath: outputURL.path) {
                print("  - Output directory: \(outputURL.path)")
            }
            if cache && fileManager.fileExists(atPath: cacheURL.path) {
                print("  - Cache directory: \(cacheURL.path)")
            }
            print("💡 Use --force to actually perform the cleanup")
        } else {
            // Clean output directory
            if fileManager.fileExists(atPath: outputURL.path) {
                do {
                    try fileManager.removeItem(at: outputURL)
                    print("✅ Removed output directory")
                } catch {
                    print("❌ Failed to remove output directory: \(error)")
                }
            }
            
            // Clean cache if requested
            if cache && fileManager.fileExists(atPath: cacheURL.path) {
                do {
                    try fileManager.removeItem(at: cacheURL)
                    print("✅ Removed cache directory")
                } catch {
                    print("❌ Failed to remove cache directory: \(error)")
                }
            }
        }
        
        print("✅ Clean command executed successfully!")
    }
}

HirundoCommand.main()
import ArgumentParser
import Foundation

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

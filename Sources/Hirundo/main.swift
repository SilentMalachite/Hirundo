import ArgumentParser
import HirundoCore
import Foundation
#if os(macOS)
import AppKit
#endif

// Error handling helper function
func handleError(_ error: Error, context: String, verbose: Bool = false) {
    if let hirundoError = error as? HirundoErrorInfo {
        print(hirundoError.userMessage)
        if verbose {
            print("\nDebug Details:")
            print("  Error Code: \(hirundoError.category.rawValue)-\(hirundoError.code)")
            print("  Details: \(hirundoError.details)")
            if !hirundoError.debugInfo.isEmpty {
                print("  Debug Info: \(hirundoError.debugInfo)")
            }
        }
    } else if let configError = error as? ConfigError {
        let hirundoError = configError.toHirundoError()
        print(hirundoError.userMessage)
        print("\n📍 Specific issue: \(configError.localizedDescription)")
    } else if let markdownError = error as? MarkdownError {
        let hirundoError = markdownError.toHirundoError()
        print(hirundoError.userMessage)
        print("\n📍 Specific issue: \(markdownError.localizedDescription)")
    } else if let templateError = error as? TemplateError {
        let hirundoError = templateError.toHirundoError()
        print(hirundoError.userMessage)
        print("\n📍 Specific issue: \(templateError.localizedDescription)")
    } else if let buildError = error as? BuildError {
        let hirundoError = buildError.toHirundoError()
        print(hirundoError.userMessage)
        print("\n📍 Specific issue: \(buildError.localizedDescription)")
    } else {
        // Generic error handling
        print("\n❌ \(context) failed")
        print("\n📍 Error: \(error.localizedDescription)")
        print("\n💡 Suggestion: Check the error message above for details")
        if verbose {
            print("\nFull error: \(error)")
        }
    }
}

@main
struct HirundoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hirundo",
        abstract: "A modern, fast, and secure static site generator built with Swift",
        version: "1.0.0",
        subcommands: [
            InitCommand.self,
            BuildCommand.self,
            ServeCommand.self,
            NewCommand.self,
            CleanCommand.self
        ]
    )
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
        let fileManager = FileManager.default
        let siteURL = URL(fileURLWithPath: path)
        
        // Check if directory exists and is not empty
        if fileManager.fileExists(atPath: path) {
            let contents = try fileManager.contentsOfDirectory(at: siteURL, includingPropertiesForKeys: nil)
            if !contents.isEmpty && !force {
                print("❌ Directory is not empty. Use --force to override.")
                throw ExitCode.failure
            }
        }
        
        print("🚀 Creating new Hirundo site at: \(path)")
        
        // Create directory structure
        try fileManager.createDirectory(at: siteURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: siteURL.appendingPathComponent("content"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: siteURL.appendingPathComponent("templates"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: siteURL.appendingPathComponent("static"), withIntermediateDirectories: true)
        
        if blog {
            try fileManager.createDirectory(at: siteURL.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        }
        
        // Create config.yaml
        let configContent = """
        site:
          title: "\(title)"
          url: "https://example.com"
          description: "A site built with Hirundo"
          language: "en-US"
          author:
            name: "Your Name"
            email: "your.email@example.com"
        
        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          staticDirectory: "static"
          templatesDirectory: "templates"
        
        server:
          port: 8080
          liveReload: true
          cors:
            enabled: true
            allowedOrigins: ["http://localhost:*", "https://localhost:*"]
            allowedMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
            allowedHeaders: ["Content-Type", "Authorization"]
            maxAge: 3600
            allowCredentials: false
        
        \(blog ? """
        blog:
          postsPerPage: 10
          generateArchive: true
          generateCategories: true
          generateTags: true
          rssEnabled: true
        """ : "")
        """
        
        try configContent.write(to: siteURL.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        
        // Create basic templates
        let baseTemplate = """
        <!DOCTYPE html>
        <html lang="{{ site.language }}">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>{% block title %}{{ page.title }} - {{ site.title }}{% endblock %}</title>
            <link rel="stylesheet" href="/css/style.css">
        </head>
        <body>
            <header>
                <h1><a href="/">{{ site.title }}</a></h1>
                <nav>
                    <a href="/">Home</a>
                    <a href="/about">About</a>
                    \(blog ? "<a href=\"/posts\">Blog</a>" : "")
                </nav>
            </header>
            <main>
                {% block content %}{% endblock %}
            </main>
            <footer>
                <p>&copy; {{ site.author.name }}</p>
            </footer>
        </body>
        </html>
        """
        
        let defaultTemplate = """
        {% extends "base.html" %}
        
        {% block content %}
        <article>
            <h1>{{ page.title }}</h1>
            {{ content }}
        </article>
        {% endblock %}
        """
        
        try baseTemplate.write(to: siteURL.appendingPathComponent("templates/base.html"), atomically: true, encoding: .utf8)
        try defaultTemplate.write(to: siteURL.appendingPathComponent("templates/default.html"), atomically: true, encoding: .utf8)
        
        if blog {
            let postTemplate = """
            {% extends "base.html" %}
            
            {% block content %}
            <article>
                <h1>{{ page.title }}</h1>
                <time>{{ page.date | date: "%B %d, %Y" }}</time>
                {% if page.categories %}
                <div class="categories">
                    Categories:
                    {% for category in page.categories %}
                    <a href="/categories/{{ category | slugify }}">{{ category }}</a>
                    {% endfor %}
                </div>
                {% endif %}
                {% if page.tags %}
                <div class="tags">
                    Tags:
                    {% for tag in page.tags %}
                    <a href="/tags/{{ tag | slugify }}">{{ tag }}</a>
                    {% endfor %}
                </div>
                {% endif %}
                {{ content }}
            </article>
            {% endblock %}
            """
            
            try postTemplate.write(to: siteURL.appendingPathComponent("templates/post.html"), atomically: true, encoding: .utf8)
        }
        
        // Create index page
        let indexContent = """
        ---
        title: "Welcome"
        layout: "default"
        ---
        
        # Welcome to \(title)
        
        This is your new Hirundo site. Start by editing this file at `content/index.md`.
        """
        
        try indexContent.write(to: siteURL.appendingPathComponent("content/index.md"), atomically: true, encoding: .utf8)
        
        // Create about page
        let aboutContent = """
        ---
        title: "About"
        layout: "default"
        ---
        
        # About
        
        This is the about page. Edit it at `content/about.md`.
        """
        
        try aboutContent.write(to: siteURL.appendingPathComponent("content/about.md"), atomically: true, encoding: .utf8)
        
        // Create basic CSS
        let cssContent = """
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        
        header {
            margin-bottom: 2rem;
            border-bottom: 1px solid #eee;
            padding-bottom: 1rem;
        }
        
        header h1 {
            margin: 0;
        }
        
        header h1 a {
            color: inherit;
            text-decoration: none;
        }
        
        nav a {
            margin-right: 1rem;
        }
        
        footer {
            margin-top: 3rem;
            padding-top: 1rem;
            border-top: 1px solid #eee;
            color: #666;
        }
        
        pre {
            background: #f4f4f4;
            padding: 1rem;
            overflow-x: auto;
        }
        
        code {
            background: #f4f4f4;
            padding: 2px 4px;
        }
        """
        
        try fileManager.createDirectory(
            at: siteURL.appendingPathComponent("static/css"),
            withIntermediateDirectories: true
        )
        try cssContent.write(
            to: siteURL.appendingPathComponent("static/css/style.css"),
            atomically: true,
            encoding: .utf8
        )
        
        // Create .gitignore
        let gitignoreContent = """
        _site/
        .DS_Store
        *.swp
        *.swo
        .hirundo-cache/
        """
        
        try gitignoreContent.write(to: siteURL.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        
        print("✅ Site created successfully!")
        print("")
        print("Next steps:")
        print("  1. cd \(path)")
        print("  2. hirundo build")
        print("  3. hirundo serve")
    }
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
        let currentDirectory = FileManager.default.currentDirectoryPath
        
        print("🔨 Building site...")
        
        do {
            let generator = try SiteGenerator(projectPath: currentDirectory)
            
            if continueOnError {
                // Use build with recovery mode
                let result = try generator.buildWithRecovery(clean: clean, includeDrafts: drafts)
                
                if result.isCompleteSuccess {
                    print("✅ Site built successfully!")
                } else {
                    print("⚠️  Build completed with errors")
                    print("✅ Successfully built: \(result.successfulPages.count) pages")
                    print("❌ Failed: \(result.failedPages.count) pages")
                    
                    // Show brief error summary
                    print("\nFailed files:")
                    for (index, failure) in result.failedPages.prefix(5).enumerated() {
                        let filename = URL(fileURLWithPath: failure.path).lastPathComponent
                        print("  \(index + 1). \(filename): \(failure.error.localizedDescription)")
                    }
                    
                    if result.failedPages.count > 5 {
                        print("  ... and \(result.failedPages.count - 5) more")
                    }
                }
                
                print("📁 Output directory: \(currentDirectory)/_site")
                
                // Exit with failure if there were errors
                if !result.isCompleteSuccess {
                    throw ExitCode.failure
                }
            } else {
                // Use standard build (fails on first error)
                try generator.build(clean: clean, includeDrafts: drafts)
                
                print("✅ Site built successfully!")
                print("📁 Output directory: \(currentDirectory)/_site")
            }
        } catch {
            handleError(error, context: "Build")
            throw ExitCode.failure
        }
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
        let currentDirectory = FileManager.default.currentDirectoryPath
        
        // First, build the site
        print("🔨 Building site...")
        do {
            let generator = try SiteGenerator(projectPath: currentDirectory)
            try generator.build()
        } catch {
            handleError(error, context: "Build")
            throw ExitCode.failure
        }
        
        // Load config to get CORS settings
        let configPath = URL(fileURLWithPath: currentDirectory).appendingPathComponent("config.yaml")
        var corsConfig: CorsConfig? = nil
        
        if FileManager.default.fileExists(atPath: configPath.path) {
            do {
                let config = try HirundoConfig.load(from: configPath)
                corsConfig = config.server.cors
            } catch {
                // Don't show stack trace for config loading during serve
                print("⚠️ Could not load CORS settings from config.yaml")
                print("Using default CORS configuration")
            }
        }
        
        // Create development server
        let server = DevelopmentServer(
            projectPath: currentDirectory,
            port: port,
            host: host,
            liveReload: !noReload,
            corsConfig: corsConfig
        )
        
        let url = "http://\(host):\(port)"
        print("🌐 Starting development server at \(url)")
        print("🔄 Live reload: \(!noReload ? "enabled" : "disabled")")
        print("🛑 Press Ctrl+C to stop")
        print("")
        
        // Open browser if requested
        if !noBrowser {
            #if os(macOS)
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
            #endif
        }
        
        // Start server
        do {
            try server.start()
        } catch {
            handleError(error, context: "Server start")
            throw ExitCode.failure
        }
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
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let postsURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent("content/posts")
        
        // Ensure posts directory exists
        try fileManager.createDirectory(at: postsURL, withIntermediateDirectories: true)
        
        // Generate slug if not provided
        let postSlug = slug ?? title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
        
        let date = Date()
        let dateFormatter = ISO8601DateFormatter()
        let dateString = dateFormatter.string(from: date)
        
        // Create post content
        let categoriesList = categories?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let tagsList = tags?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        
        var frontMatter = """
        ---
        title: "\(title)"
        date: \(dateString)
        """
        
        if draft {
            frontMatter += "\ndraft: true"
        }
        
        if !categoriesList.isEmpty {
            frontMatter += "\ncategories: [" + categoriesList.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
        }
        
        if !tagsList.isEmpty {
            frontMatter += "\ntags: [" + tagsList.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
        }
        
        frontMatter += """
        \nlayout: "post"
        ---
        
        # \(title)
        
        Write your post content here.
        """
        
        let postPath = postsURL.appendingPathComponent("\(postSlug).md")
        
        // Check if file already exists
        if fileManager.fileExists(atPath: postPath.path) {
            print("❌ Post already exists: \(postPath.path)")
            throw ExitCode.failure
        }
        
        try frontMatter.write(to: postPath, atomically: true, encoding: .utf8)
        
        print("✅ Created new post: \(postPath.path)")
        
        if open {
            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "open"
            
            // Enhanced editor command validation
            guard let validatedEditor = SecurityUtilities.validateAndSanitizeEditorCommand(editor) else {
                print("⚠️ Editor '\(editor)' failed security validation.")
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [validatedEditor, postPath.path]
            
            do {
                try process.run()
            } catch {
                print("⚠️ Failed to open editor '\(validatedEditor)': \(error.localizedDescription)")
            }
        }
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
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let contentURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent("content")
        
        // Determine page path
        let pagePath: String
        if let providedPath = path {
            pagePath = providedPath.hasSuffix(".md") ? providedPath : "\(providedPath).md"
        } else {
            let slug = title
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
            pagePath = "\(slug).md"
        }
        
        let pageURL = contentURL.appendingPathComponent(pagePath)
        
        // Ensure parent directory exists
        try fileManager.createDirectory(
            at: pageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // Create page content
        let pageContent = """
        ---
        title: "\(title)"
        layout: "\(layout)"
        ---
        
        # \(title)
        
        Write your page content here.
        """
        
        // Check if file already exists
        if fileManager.fileExists(atPath: pageURL.path) {
            print("❌ Page already exists: \(pageURL.path)")
            throw ExitCode.failure
        }
        
        try pageContent.write(to: pageURL, atomically: true, encoding: .utf8)
        
        print("✅ Created new page: \(pageURL.path)")
        
        if open {
            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "open"
            
            // Enhanced editor command validation
            guard let validatedEditor = SecurityUtilities.validateAndSanitizeEditorCommand(editor) else {
                print("⚠️ Editor '\(editor)' failed security validation.")
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [validatedEditor, pageURL.path]
            
            do {
                try process.run()
            } catch {
                print("⚠️ Failed to open editor '\(validatedEditor)': \(error.localizedDescription)")
            }
        }
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
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let outputURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent("_site")
        let cacheURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent(".hirundo-cache")
        
        if !force {
            print("⚠️  This will delete:")
            if fileManager.fileExists(atPath: outputURL.path) {
                print("  - Output directory: \(outputURL.path)")
            }
            if cache && fileManager.fileExists(atPath: cacheURL.path) {
                print("  - Cache directory: \(cacheURL.path)")
            }
            print("")
            print("Continue? (y/N): ", terminator: "")
            
            if let response = readLine()?.lowercased(), response != "y" {
                print("Cancelled.")
                return
            }
        }
        
        print("🧹 Cleaning...")
        
        // Clean output directory
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
            print("✅ Removed output directory")
        }
        
        // Clean cache if requested
        if cache && fileManager.fileExists(atPath: cacheURL.path) {
            try fileManager.removeItem(at: cacheURL)
            print("✅ Removed cache directory")
        }
        
        print("✨ Clean complete!")
    }
}


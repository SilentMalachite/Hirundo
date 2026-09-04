import Foundation

public enum ConfigError: Error, LocalizedError {
    case invalidFormat(String)
    case missingRequiredField(String)
    case fileNotFound(String)
    case parseError(String)
    case invalidValue(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let details):
            return "Invalid configuration format: \(details)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .fileNotFound(let path):
            return "Configuration file not found: \(path)"
        case .parseError(let details):
            return "Failed to parse configuration: \(details)"
        case .invalidValue(let details):
            return "Invalid configuration value: \(details)"
        }
    }
}

public enum MarkdownError: Error, LocalizedError {
    case invalidFrontMatter(String)
    case parseError(String)
    case contentTooLarge(String)
    case frontMatterTooLarge(String)
    case frontMatterValueTooLarge(String)
    case excessiveNesting(String)
    case dangerousContent(String)
    case excessiveRepetition(String)
    case fileNotFound(String)
    case invalidEncoding
    
    public var errorDescription: String? {
        switch self {
        case .invalidFrontMatter(let details):
            return "Invalid front matter: \(details)"
        case .parseError(let details):
            return "Failed to parse markdown: \(details)"
        case .contentTooLarge(let details):
            return "Markdown content too large: \(details)"
        case .frontMatterTooLarge(let details):
            return "Front matter too large: \(details)"
        case .frontMatterValueTooLarge(let details):
            return "Front matter value too large: \(details)"
        case .excessiveNesting(let details):
            return "Excessive nesting detected: \(details)"
        case .dangerousContent(let details):
            return "Dangerous content detected: \(details)"
        case .excessiveRepetition(let details):
            return "Excessive repetition detected: \(details)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidEncoding:
            return "Invalid file encoding (expected UTF-8)"
        }
    }
}

public enum TemplateError: Error, LocalizedError {
    case templateNotFound(String)
    case renderError(String)
    case invalidTemplate(String)
    
    public var errorDescription: String? {
        switch self {
        case .templateNotFound(let name):
            return "Template not found: \(name)"
        case .renderError(let details):
            return "Failed to render template: \(details)"
        case .invalidTemplate(let details):
            return "Invalid template: \(details)"
        }
    }
}

public enum BuildError: Error, LocalizedError {
    case configurationError(String)
    case contentError(String)
    case templateError(String)
    case outputError(String)
    
    public var errorDescription: String? {
        switch self {
        case .configurationError(let details):
            return "Configuration error: \(details)"
        case .contentError(let details):
            return "Content error: \(details)"
        case .templateError(let details):
            return "Template error: \(details)"
        case .outputError(let details):
            return "Output error: \(details)"
        }
    }
}

/// Errors raised while scaffolding a new Hirundo site.
public enum ScaffoldError: Error, LocalizedError, Equatable, Sendable {
    case emptyDestinationPath
    case destinationNotEmpty(String)
    case destinationIsFile(String)
    case invalidTitle(String)
    case cannotCreateDirectory(String)
    case cannotWriteFile(String)
    case cannotReadDirectory(String)
    case cannotReadFile(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDestinationPath:
            return "Destination path is empty. Pass a directory path, or \".\" for the current directory."
        case .destinationNotEmpty(let path):
            return "Directory is not empty: \(path). Use --force to override."
        case .destinationIsFile(let path):
            return "Destination exists and is a file: \(path)"
        case .invalidTitle(let details):
            return "Invalid site title: \(details)"
        case .cannotCreateDirectory(let path):
            return "Could not create directory: \(path)"
        case .cannotWriteFile(let path):
            return "Could not write file: \(path)"
        case .cannotReadDirectory(let path):
            return "Could not read directory: \(path)"
        case .cannotReadFile(let path):
            return "Could not read file: \(path)"
        }
    }
}

extension ScaffoldError {
    /// Converts this scaffold error into the unified Hirundo error representation.
    ///
    /// The category decides the headline the CLI prints, so usage mistakes (an unusable
    /// `--title`) are reported as configuration problems rather than disk failures, and the
    /// cases a user can act on carry their own suggestion instead of the generic
    /// "check permissions and disk space" advice.
    /// - Returns: A `HirundoErrorInfo` with a stable code, a category matching the real
    ///   cause, and an error-specific suggestion where one is useful.
    public func toHirundoError() -> HirundoErrorInfo {
        let code: String
        let category: ErrorCategory
        let suggestion: String?
        switch self {
        case .emptyDestinationPath:
            code = "EMPTY_PATH"
            category = .configuration
            suggestion = "Pass a directory path such as 'my-site', or '.' to scaffold "
                + "into the current directory"
        case .destinationNotEmpty:
            code = "DEST_NOT_EMPTY"
            category = .filesystem
            suggestion = "Re-run with --force to scaffold into the existing directory, "
                + "or choose an empty directory"
        case .destinationIsFile:
            code = "DEST_IS_FILE"
            category = .filesystem
            suggestion = "Choose a directory path, or move the existing file out of the way"
        case .invalidTitle:
            code = "INVALID_TITLE"
            category = .configuration
            suggestion = "Pass a usable --title, for example --title \"My Site\""
        case .cannotCreateDirectory:
            code = "CREATE_DIR_FAILED"
            category = .filesystem
            suggestion = nil
        case .cannotWriteFile:
            code = "WRITE_FAILED"
            category = .filesystem
            suggestion = nil
        case .cannotReadDirectory:
            code = "READ_DIR_FAILED"
            category = .filesystem
            suggestion = nil
        case .cannotReadFile:
            code = "READ_FILE_FAILED"
            category = .filesystem
            suggestion = nil
        }
        return HirundoErrorInfo(
            category: category,
            code: code,
            details: self.localizedDescription,
            suggestion: suggestion,
            underlyingError: self
        )
    }
}

// Unified error system for consistent error handling
public protocol HirundoError: Error, LocalizedError {
    var category: ErrorCategory { get }
    var code: String { get }
    var details: String { get }
    var underlyingError: Error? { get }
    var userMessage: String { get }
    var debugInfo: [String: AnyCodable] { get }
}

public enum ErrorCategory: String, CaseIterable, Sendable {
    case configuration = "CONFIG"
    case markdown = "MARKDOWN"
    case template = "TEMPLATE"
    case build = "BUILD"
    case asset = "ASSET"
    case hotReload = "HOTRELOAD"
    case server = "SERVER"
    case network = "NETWORK"
    case filesystem = "FILESYSTEM"
}

extension ErrorCategory {
    /// Headline shown to the user for errors in this category.
    var userFacingTitle: String {
        switch self {
        case .configuration: return "Configuration Issue"
        case .markdown: return "Content Processing Issue"
        case .template: return "Template Issue"
        case .build: return "Build Failed"
        case .asset: return "Asset Processing Issue"
        case .hotReload: return "Live Reload Issue"
        case .server: return "Server Error"
        case .network: return "Network Error"
        case .filesystem: return "File System Error"
        }
    }

    /// One-line, jargon-free explanation of what went wrong in this category.
    var userFacingDescription: String {
        switch self {
        case .configuration: return "Check your config.yaml file for errors."
        case .markdown: return "One of your markdown files couldn't be processed."
        case .template: return "A template file has errors or is missing."
        case .build: return "The site couldn't be built due to an error."
        case .asset: return "Static files couldn't be processed."
        case .hotReload: return "File watching encountered a problem."
        case .server: return "The development server encountered an issue."
        case .network: return "A network operation failed."
        case .filesystem: return "A file operation failed."
        }
    }

    /// Fallback next step, used when an error carries no more specific suggestion.
    var defaultSuggestedAction: String {
        switch self {
        case .configuration: return "Run 'hirundo validate' to check your configuration"
        case .markdown: return "Check the file mentioned in the error for syntax issues"
        case .template: return "Ensure all required templates exist in the templates directory"
        case .build: return "Review the error details above and fix the mentioned issues"
        case .asset: return "Check that all referenced assets exist in the static directory"
        case .hotReload: return "Try restarting the development server"
        case .server: return "Check if the port is already in use or try a different port"
        case .network: return "Check your internet connection and try again"
        case .filesystem: return "Check file permissions and available disk space"
        }
    }
}

public struct HirundoErrorInfo: HirundoError {
    public let category: ErrorCategory
    public let code: String
    public let details: String
    public let underlyingError: Error?
    public let debugInfo: [String: AnyCodable]

    /// Error-specific next step, overriding the category default when present.
    public let suggestion: String?

    /// The action recommended to the user: the error's own `suggestion` when it has one,
    /// otherwise the default suggestion for its category.
    public var suggestedAction: String {
        suggestion ?? category.defaultSuggestedAction
    }

    /// Creates a unified error description.
    /// - Parameters:
    ///   - category: Broad area the failure belongs to; drives the headline shown to users.
    ///   - code: Stable, machine-readable identifier for this failure.
    ///   - details: Human-readable description of what went wrong.
    ///   - suggestion: Error-specific next step. When `nil`, the category's default
    ///     suggestion is used instead.
    ///   - underlyingError: The originating error, if any.
    ///   - debugInfo: Extra context surfaced in verbose mode.
    public init(
        category: ErrorCategory,
        code: String,
        details: String,
        suggestion: String? = nil,
        underlyingError: Error? = nil,
        debugInfo: [String: AnyCodable] = [:]
    ) {
        self.category = category
        self.code = code
        self.details = details
        self.suggestion = suggestion
        self.underlyingError = underlyingError
        self.debugInfo = debugInfo
    }
    
    public var errorDescription: String? {
        return "\(category.rawValue)-\(code): \(details)"
    }
    
    public var userMessage: String {
        // Provide helpful, actionable messages without technical jargon
        return formatUserMessage(
            category.userFacingTitle,
            category.userFacingDescription,
            suggestedAction: suggestedAction
        )
    }
    
    private func formatUserMessage(_ title: String, _ description: String, suggestedAction: String) -> String {
        """
        
        ❌ \(title)
        
        \(description)
        
        💡 Suggestion: \(suggestedAction)
        
        For more details, run with --verbose flag.
        """
    }
}

// Error conversion utilities
extension ConfigError {
    public func toHirundoError() -> HirundoErrorInfo {
        let code: String
        switch self {
        case .invalidFormat: code = "INVALID_FORMAT"
        case .missingRequiredField: code = "MISSING_FIELD"
        case .fileNotFound: code = "FILE_NOT_FOUND"
        case .parseError: code = "PARSE_ERROR"
        case .invalidValue: code = "INVALID_VALUE"
        }
        
        return HirundoErrorInfo(
            category: .configuration,
            code: code,
            details: self.localizedDescription,
            underlyingError: self
        )
    }
}

extension MarkdownError {
    public func toHirundoError() -> HirundoErrorInfo {
        let code: String
        switch self {
        case .invalidFrontMatter: code = "INVALID_FRONTMATTER"
        case .parseError: code = "PARSE_ERROR"
        case .contentTooLarge: code = "CONTENT_TOO_LARGE"
        case .frontMatterTooLarge: code = "FRONTMATTER_TOO_LARGE"
        case .frontMatterValueTooLarge: code = "FRONTMATTER_VALUE_TOO_LARGE"
        case .excessiveNesting: code = "EXCESSIVE_NESTING"
        case .dangerousContent: code = "DANGEROUS_CONTENT"
        case .excessiveRepetition: code = "EXCESSIVE_REPETITION"
        case .fileNotFound: code = "FILE_NOT_FOUND"
        case .invalidEncoding: code = "INVALID_ENCODING"
        }
        
        return HirundoErrorInfo(
            category: .markdown,
            code: code,
            details: self.localizedDescription,
            underlyingError: self
        )
    }
}

extension TemplateError {
    public func toHirundoError() -> HirundoErrorInfo {
        let code: String
        switch self {
        case .templateNotFound: code = "TEMPLATE_NOT_FOUND"
        case .renderError: code = "RENDER_ERROR"
        case .invalidTemplate: code = "INVALID_TEMPLATE"
        }
        
        return HirundoErrorInfo(
            category: .template,
            code: code,
            details: self.localizedDescription,
            underlyingError: self
        )
    }
}

extension BuildError {
    public func toHirundoError() -> HirundoErrorInfo {
        let code: String
        switch self {
        case .configurationError: code = "CONFIGURATION_ERROR"
        case .contentError: code = "CONTENT_ERROR"
        case .templateError: code = "TEMPLATE_ERROR"
        case .outputError: code = "OUTPUT_ERROR"
        }
        
        return HirundoErrorInfo(
            category: .build,
            code: code,
            details: self.localizedDescription,
            underlyingError: self
        )
    }
}

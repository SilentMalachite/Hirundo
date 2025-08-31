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

public struct HirundoErrorInfo: HirundoError {
    public let category: ErrorCategory
    public let code: String
    public let details: String
    public let underlyingError: Error?
    public let debugInfo: [String: AnyCodable]
    
    public init(
        category: ErrorCategory,
        code: String,
        details: String,
        underlyingError: Error? = nil,
        debugInfo: [String: AnyCodable] = [:]
    ) {
        self.category = category
        self.code = code
        self.details = details
        self.underlyingError = underlyingError
        self.debugInfo = debugInfo
    }
    
    public var errorDescription: String? {
        return "\(category.rawValue)-\(code): \(details)"
    }
    
    public var userMessage: String {
        // Provide helpful, actionable messages without technical jargon
        switch category {
        case .configuration:
            return formatUserMessage(
                "Configuration Issue",
                "Check your config.yaml file for errors.",
                suggestedAction: "Run 'hirundo validate' to check your configuration"
            )
        case .markdown:
            return formatUserMessage(
                "Content Processing Issue",
                "One of your markdown files couldn't be processed.",
                suggestedAction: "Check the file mentioned in the error for syntax issues"
            )
        case .template:
            return formatUserMessage(
                "Template Issue",
                "A template file has errors or is missing.",
                suggestedAction: "Ensure all required templates exist in the templates directory"
            )
        case .build:
            return formatUserMessage(
                "Build Failed",
                "The site couldn't be built due to an error.",
                suggestedAction: "Review the error details above and fix the mentioned issues"
            )
        case .asset:
            return formatUserMessage(
                "Asset Processing Issue",
                "Static files couldn't be processed.",
                suggestedAction: "Check that all referenced assets exist in the static directory"
            )
        case .hotReload:
            return formatUserMessage(
                "Live Reload Issue",
                "File watching encountered a problem.",
                suggestedAction: "Try restarting the development server"
            )
        case .server:
            return formatUserMessage(
                "Server Error",
                "The development server encountered an issue.",
                suggestedAction: "Check if the port is already in use or try a different port"
            )
        case .network:
            return formatUserMessage(
                "Network Error",
                "A network operation failed.",
                suggestedAction: "Check your internet connection and try again"
            )
        case .filesystem:
            return formatUserMessage(
                "File System Error",
                "A file operation failed.",
                suggestedAction: "Check file permissions and available disk space"
            )
        }
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

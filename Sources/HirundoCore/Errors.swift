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
    var debugInfo: [String: Any] { get }
}

public enum ErrorCategory: String, CaseIterable {
    case configuration = "CONFIG"
    case markdown = "MARKDOWN"
    case template = "TEMPLATE"
    case build = "BUILD"
    case asset = "ASSET"
    case plugin = "PLUGIN"
    case hotReload = "HOTRELOAD"
    case server = "SERVER"
}

public struct HirundoErrorInfo: HirundoError {
    public let category: ErrorCategory
    public let code: String
    public let details: String
    public let underlyingError: Error?
    public let debugInfo: [String: Any]
    
    public init(
        category: ErrorCategory,
        code: String,
        details: String,
        underlyingError: Error? = nil,
        debugInfo: [String: Any] = [:]
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
        switch category {
        case .configuration:
            return "There's an issue with your configuration file."
        case .markdown:
            return "There's an issue processing your markdown content."
        case .template:
            return "There's an issue with your template files."
        case .build:
            return "Build failed due to an error."
        case .asset:
            return "There's an issue processing your assets."
        case .plugin:
            return "A plugin encountered an error."
        case .hotReload:
            return "File watching encountered an error."
        case .server:
            return "Development server encountered an error."
        }
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
import Foundation
import Stencil
import PathKit

/// Thread-safety: mutations of environment and siteConfig are guarded by environmentQueue with .barrier; other properties are immutable after init.
public class TemplateEngine: @unchecked Sendable {
    private var environment: Environment
    private let templatesDirectory: String
    private var siteConfig: Site?
    private let environmentQueue = DispatchQueue(label: "com.hirundo.environment", attributes: .concurrent)
    
    // Component managers
    private let templateCache: TemplateCache
    
    public init(templatesDirectory: String) {
        self.templatesDirectory = templatesDirectory
        self.templateCache = TemplateCache()
        
        let loader = FileSystemLoader(paths: [Path(templatesDirectory)])
        
        var ext = Extension()
        TemplateFilters.registerStaticFilters(to: &ext)
        
        self.environment = Environment(
            loader: loader,
            extensions: [ext]
        )
    }
    
    public func configure(with siteConfig: Site) {
        environmentQueue.sync(flags: .barrier) {
            self.siteConfig = siteConfig
            
            // Re-register filters with site config
            var ext = Extension()
            TemplateFilters.registerStaticFilters(to: &ext)
            TemplateFilters.registerDynamicFilters(to: &ext, siteConfig: siteConfig)
            
            // Update environment with new extension
            let loader = FileSystemLoader(paths: [Path(templatesDirectory)])
            self.environment = Environment(
                loader: loader,
                extensions: [ext]
            )
            
            // Clear template cache since environment changed
            templateCache.clearCache()
        }
    }
    
    public func render(template: String, context: [String: Any]) throws -> String {
        do {
            let templateObj = try getTemplate(name: template)
            return try templateObj.render(context)
        } catch _ as TemplateDoesNotExist {
            throw TemplateError.templateNotFound(template)
        } catch {
            throw TemplateError.renderError(error.localizedDescription)
        }
    }
    
    public func clearCache() {
        templateCache.clearCache()
    }
    
    public func registerCustomFilters() {
        // Filters are already registered in init
        // This method exists for compatibility with tests
    }
    
    /// Validate template syntax without rendering
    public func validateTemplate(name: String) throws {
        let templatePath = Path(templatesDirectory) + name
        guard templatePath.exists else {
            throw TemplateEngineError.templateNotFound(name)
        }
        
        do {
            let templateContent: String = try templatePath.read()
            _ = environment.templateClass.init(templateString: templateContent, environment: environment)
        } catch {
            throw TemplateEngineError.syntaxError(name, error.localizedDescription)
        }
    }
    
    private func getTemplate(name: String) throws -> Template {
        // First, check cache
        if let cached = templateCache.getTemplate(for: name) {
            return cached
        }
        
        // If not in cache, load template from file system
        let template = try environment.loadTemplate(name: name)
        
        // Store in cache
        templateCache.setTemplate(template, for: name)
        
        return template
    }
}

// MARK: - Template Engine Errors

public enum TemplateEngineError: LocalizedError {
    case templateNotFound(String)
    case syntaxError(String, String)
    case templatesDirectoryNotFound(String)
    case multipleValidationErrors([String])
    
    public var errorDescription: String? {
        switch self {
        case .templateNotFound(let name):
            return "Template not found: \(name)"
        case .syntaxError(let name, let error):
            return "Syntax error in template \(name): \(error)"
        case .templatesDirectoryNotFound(let path):
            return "Templates directory not found: \(path)"
        case .multipleValidationErrors(let errors):
            return "Multiple template validation errors:\n" + errors.joined(separator: "\n")
        }
    }
}

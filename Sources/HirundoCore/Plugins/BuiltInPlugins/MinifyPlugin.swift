import Foundation

// Asset minification plugin
public class MinifyPlugin: Plugin {
    public let metadata = PluginMetadata(
        name: "MinifyPlugin",
        version: "1.0.0",
        author: "Hirundo",
        description: "Minifies CSS and JavaScript files",
        priority: .high // Run before other asset processors
    )
    
    private var minifyCSS: Bool = true
    private var minifyJS: Bool = true
    private var removeComments: Bool = true
    
    public init() {}
    
    public func initialize(context: PluginContext) throws {}
    
    public func cleanup() throws {}
    
    public func configure(with config: PluginConfig) throws {
        if let css = config.settings["minifyCSS"] as? Bool {
            minifyCSS = css
        }
        if let js = config.settings["minifyJS"] as? Bool {
            minifyJS = js
        }
        if let comments = config.settings["removeComments"] as? Bool {
            removeComments = comments
        }
    }
    
    public func processAsset(_ asset: AssetItem) throws -> AssetItem {
        var processed = asset
        
        switch asset.type {
        case .css where minifyCSS:
            let content = try String(contentsOfFile: asset.sourcePath, encoding: .utf8)
            let minified = minifyCSSContent(content)
            
            // Write minified content
            try minified.write(toFile: asset.outputPath, atomically: true, encoding: .utf8)
            
            processed.processed = true
            processed.metadata["minified"] = true
            processed.metadata["originalSize"] = content.count
            processed.metadata["minifiedSize"] = minified.count
            
        case .javascript where minifyJS:
            let content = try String(contentsOfFile: asset.sourcePath, encoding: .utf8)
            let minified = minifyJSContent(content)
            
            // Write minified content
            try minified.write(toFile: asset.outputPath, atomically: true, encoding: .utf8)
            
            processed.processed = true
            processed.metadata["minified"] = true
            processed.metadata["originalSize"] = content.count
            processed.metadata["minifiedSize"] = minified.count
            
        default:
            // Copy file as-is
            if asset.sourcePath != asset.outputPath {
                try FileManager.default.copyItem(
                    atPath: asset.sourcePath,
                    toPath: asset.outputPath
                )
            }
        }
        
        return processed
    }
    
    private func minifyCSSContent(_ content: String) -> String {
        var minified = content
        
        if removeComments {
            // Remove CSS comments
            minified = minified.replacingOccurrences(
                of: "/\\*[^*]*\\*+(?:[^/*][^*]*\\*+)*/",
                with: "",
                options: .regularExpression
            )
        }
        
        // Remove unnecessary whitespace
        minified = minified
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *{ *", with: "{", options: .regularExpression)
            .replacingOccurrences(of: " *} *", with: "}", options: .regularExpression)
            .replacingOccurrences(of: " *: *", with: ":", options: .regularExpression)
            .replacingOccurrences(of: " *; *", with: ";", options: .regularExpression)
            .replacingOccurrences(of: " *, *", with: ",", options: .regularExpression)
            .replacingOccurrences(of: ";}", with: "}", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return minified
    }
    
    private func minifyJSContent(_ content: String) -> String {
        var minified = content
        
        if removeComments {
            // Remove single-line comments (careful not to break URLs)
            minified = minified.replacingOccurrences(
                of: "(?<!:)//[^\n]*",
                with: "",
                options: .regularExpression
            )
            
            // Remove multi-line comments
            minified = minified.replacingOccurrences(
                of: "/\\*[^*]*\\*+(?:[^/*][^*]*\\*+)*/",
                with: "",
                options: .regularExpression
            )
        }
        
        // Basic minification (production would use a proper JS parser)
        minified = minified
            .replacingOccurrences(of: "\n+", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\t+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *= *", with: "=", options: .regularExpression)
            .replacingOccurrences(of: " *\\+ *", with: "+", options: .regularExpression)
            .replacingOccurrences(of: " *- *", with: "-", options: .regularExpression)
            .replacingOccurrences(of: " *\\* *", with: "*", options: .regularExpression)
            .replacingOccurrences(of: " */ *", with: "/", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return minified
    }
}
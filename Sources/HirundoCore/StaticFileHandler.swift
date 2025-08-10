import Foundation

/// Responsible for handling static files and assets
public final class StaticFileHandler {
    private let fileManager: FileManager
    private let assetPipeline: AssetPipeline
    
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        // Create a basic plugin manager for asset pipeline
        let pluginManager = PluginManager()
        self.assetPipeline = AssetPipeline(pluginManager: pluginManager)
    }
    
    /// Copy static files from source to destination
    public func copyStaticFiles(from sourcePath: String, to destinationPath: String) throws {
        guard fileManager.fileExists(atPath: sourcePath) else {
            // No static directory is okay
            return
        }
        
        let destinationURL = URL(fileURLWithPath: destinationPath)
        
        // Create destination directory if needed
        try fileManager.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Process assets through pipeline
        _ = try assetPipeline.processAssets(from: sourcePath, to: destinationPath)
    }
    
    /// Check if an asset should be processed
    private func shouldProcessAsset(_ asset: AssetItem) -> Bool {
        switch asset.type {
        case .css, .javascript:
            return true
        case .image:
            return false // Images are handled separately if needed
        case .other:
            return false
        }
    }
    
    /// Process and copy an asset
    private func processAndCopyAsset(_ asset: AssetItem, to destinationPath: String) throws {
        let content = try String(contentsOfFile: asset.sourcePath, encoding: .utf8)
        
        let processed: String
        switch asset.type {
        case .css:
            processed = assetPipeline.processCSS(content)
        case .javascript:
            processed = assetPipeline.processJS(content)
        default:
            processed = content
        }
        
        try processed.write(toFile: destinationPath, atomically: true, encoding: .utf8)
    }
    
    /// Copy a file from source to destination
    internal func copyFile(from source: String, to destination: String) throws {
        // Remove existing file if it exists
        if fileManager.fileExists(atPath: destination) {
            try fileManager.removeItem(atPath: destination)
        }
        
        try fileManager.copyItem(atPath: source, toPath: destination)
    }
    
    /// Clean the output directory
    public func cleanOutputDirectory(_ path: String) throws {
        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
        
        try fileManager.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

// URL extension for relative path calculation
extension URL {
    func relativePath(from base: URL) -> String? {
        // Ensure both URLs are standardized
        let basePath = base.standardized.path
        let selfPath = self.standardized.path
        
        // Check if self is under base
        guard selfPath.hasPrefix(basePath) else {
            return nil
        }
        
        // Calculate relative path
        var relativePath = String(selfPath.dropFirst(basePath.count))
        if relativePath.hasPrefix("/") {
            relativePath = String(relativePath.dropFirst())
        }
        
        return relativePath.isEmpty ? nil : relativePath
    }
}
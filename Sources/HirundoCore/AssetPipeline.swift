import Foundation

// AssetConcatenationRule is defined in Assets/AssetConcatenationRule.swift

// Asset pipeline for processing static assets
public class AssetPipeline {
    private let fileManager = FileManager.default
    
    // Component managers
    private let processor: AssetProcessor
    private let fileManagerHelper: AssetFileManager
    private let concatenator: AssetConcatenator
    
    // Configuration
    public var enableFingerprinting: Bool = false
    public var enableSourceMaps: Bool = false
    public var excludePatterns: [String] = []
    public var concatenationRules: [AssetConcatenationRule] = []
    public var cssOptions: CSSProcessingOptions = CSSProcessingOptions()
    public var jsOptions: JSProcessingOptions = JSProcessingOptions()
    
    public init() {
        self.processor = AssetProcessor()
        self.fileManagerHelper = AssetFileManager()
        self.concatenator = AssetConcatenator()
    }
    
    // Process all assets from source to destination
    public func processAssets(from sourcePath: String, to destinationPath: String) throws -> [String: String] {
        var manifest: [String: String] = [:]
        
        // Create destination directory
        try fileManager.createDirectory(
            atPath: destinationPath,
            withIntermediateDirectories: true
        )
        
        // First, handle concatenation rules
        if !concatenationRules.isEmpty {
            try concatenator.processConcatenationRules(
                concatenationRules,
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                enableFingerprinting: enableFingerprinting,
                manifest: &manifest
            )
        }
        
        // Process individual assets
        let sourceURL = URL(fileURLWithPath: sourcePath)
        try fileManagerHelper.processDirectory(
            sourceURL,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            excludePatterns: excludePatterns,
            concatenationRules: concatenationRules
        ) { fileURL, relativePath in
            try self.processFile(
                fileURL,
                relativePath: relativePath,
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                manifest: &manifest
            )
        }
        
        return manifest
    }
    
    // Detect asset type from filename
    public func detectAssetType(for filename: String) -> AssetItem.AssetType {
        return processor.detectAssetType(for: filename)
    }
    
    // Save manifest to file
    public func saveManifest(_ manifest: [String: String], to path: String) throws {
        try fileManagerHelper.saveManifest(manifest, to: path)
    }
    
    // Load manifest from file
    public func loadManifest(from path: String) throws -> [String: String] {
        return try fileManagerHelper.loadManifest(from: path)
    }
    

    
    // Process a single file
    private func processFile(
        _ fileURL: URL,
        relativePath: String,
        sourcePath: String,
        destinationPath: String,
        manifest: inout [String: String]
    ) throws {
        let assetType = processor.detectAssetType(for: fileURL.lastPathComponent)
        
        // Basic path validation and destination confinement
        let sanitizedRelativePath = relativePath
        
        // Compute destination root and candidate output path, resolving symlinks
        let destinationRootURL = URL(fileURLWithPath: destinationPath).resolvingSymlinksInPath()
        let candidateOutputURL = destinationRootURL.appendingPathComponent(sanitizedRelativePath).resolvingSymlinksInPath()
        
        // Ensure the output stays within destination root
        let rootPath = destinationRootURL.path.hasSuffix("/") ? destinationRootURL.path : destinationRootURL.path + "/"
        let candidatePath = candidateOutputURL.path.hasSuffix("/") ? candidateOutputURL.path : candidateOutputURL.path
        guard candidatePath == destinationRootURL.path || candidatePath.hasPrefix(rootPath) else {
            throw AssetPipelineError.processingFailed("Output path escapes destination directory: \(candidatePath)")
        }
        
        // Create asset item
        var outputPath = candidateOutputURL.path
        
        // Generate fingerprint if enabled
        let fingerprint: String?
        if enableFingerprinting {
            fingerprint = try processor.generateFingerprint(for: fileURL)
            guard let validFingerprint = fingerprint else {
                throw AssetPipelineError.processingFailed("Failed to generate fingerprint for file: \(fileURL.path)")
            }
            outputPath = processor.addFingerprint(to: outputPath, fingerprint: validFingerprint)
        } else {
            fingerprint = nil
        }
        
        // Ensure output directory exists
        let outputURL = URL(fileURLWithPath: outputPath)
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // Create asset item for plugin processing
        let asset = AssetItem(
            sourcePath: fileURL.path,
            outputPath: outputPath,
            type: assetType
        )
        
        // Process through built-in pipeline first
        try processor.processAssetContent(asset, cssOptions: cssOptions, jsOptions: jsOptions)
        
        // No external plugins in Stage 2; built-in pipeline already wrote output
        
        // Update manifest
        if enableFingerprinting {
            manifest[relativePath] = outputURL.lastPathComponent
        }
    }
    
    // Process CSS content
    public func processCSS(_ content: String, options: CSSProcessingOptions = CSSProcessingOptions()) -> String {
        return processor.processCSS(content, options: options)
    }
    
    // Process JavaScript content
    public func processJS(_ content: String, options: JSProcessingOptions = JSProcessingOptions()) -> String {
        return processor.processJS(content, options: options)
    }
    

}

// AssetPipelineError is defined in Assets/AssetPipelineError.swift

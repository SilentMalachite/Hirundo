import Foundation

/// Handles asset concatenation operations
public class AssetConcatenator {
    private let fileManager = FileManager.default
    private let fileManagerHelper: AssetFileManager
    
    public init() {
        self.fileManagerHelper = AssetFileManager()
    }
    
    /// Processes concatenation rules
    public func processConcatenationRules(
        _ rules: [AssetConcatenationRule],
        sourcePath: String,
        destinationPath: String,
        enableFingerprinting: Bool,
        manifest: inout [String: String]
    ) throws {
        for rule in rules {
            let files = try fileManagerHelper.findFiles(matching: rule.pattern, in: sourcePath)
            
            if files.isEmpty {
                continue
            }
            
            // Concatenate files
            var concatenatedContent = ""
            for (index, file) in files.enumerated() {
                if index > 0 {
                    concatenatedContent += rule.separator
                }
                concatenatedContent += try String(contentsOfFile: file, encoding: .utf8)
            }
            
            // Write concatenated file
            let outputPath = URL(fileURLWithPath: destinationPath)
                .appendingPathComponent(rule.output)
            
            try fileManager.createDirectory(
                at: outputPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            // Apply fingerprinting if enabled
            var finalOutputPath = outputPath.path
            if enableFingerprinting {
                let processor = AssetProcessor()
                let fingerprint = processor.generateFingerprint(for: concatenatedContent)
                finalOutputPath = processor.addFingerprint(to: finalOutputPath, fingerprint: fingerprint)
                manifest[rule.output] = URL(fileURLWithPath: finalOutputPath).lastPathComponent
            }
            
            try concatenatedContent.write(to: URL(fileURLWithPath: finalOutputPath), atomically: true, encoding: .utf8)
        }
    }
}
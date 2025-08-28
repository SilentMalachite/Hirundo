import Foundation

/// アセットパイプラインエラー
public enum AssetPipelineError: Error, LocalizedError {
    case pathTraversalAttempt(String)
    case unsupportedAssetType(String)
    case processingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .pathTraversalAttempt(let path):
            return "Path traversal attempt detected: \(path)"
        case .unsupportedAssetType(let type):
            return "Unsupported asset type: \(type)"
        case .processingFailed(let reason):
            return "Asset processing failed: \(reason)"
        }
    }
}
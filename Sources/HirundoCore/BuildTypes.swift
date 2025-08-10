import Foundation

// Build result types for error recovery
public struct BuildResult {
    public let success: Bool
    public let errors: [BuildErrorDetail]
    public let successCount: Int
    public let failCount: Int
    
    public init(success: Bool, errors: [BuildErrorDetail], successCount: Int, failCount: Int) {
        self.success = success
        self.errors = errors
        self.successCount = successCount
        self.failCount = failCount
    }
}

// Build error information
public struct BuildErrorDetail {
    public let file: String
    public let stage: BuildStage
    public let error: Error
    public let recoverable: Bool
    
    public init(file: String, stage: BuildStage, error: Error, recoverable: Bool) {
        self.file = file
        self.stage = stage
        self.error = error
        self.recoverable = recoverable
    }
}

// Build stages
public enum BuildStage {
    case parsing
    case rendering
    case writing
    case unknown
}
import Foundation

// Build result types for error recovery
//
// `BuildResult` crosses an actor boundary: `RebuildCoordinator` awaits the build closure and
// reads the result inside the actor. Everything reachable from it is therefore `Sendable`.
public struct BuildResult: Sendable {
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

/// An error kept for reporting after the fact.
///
/// The errors a build collects come out of `catch` blocks, so their static type is `any Error`,
/// which is not `Sendable` — and `Sendable` is a marker protocol, so no cast can narrow one to
/// the sendable errors among them. Nothing reads these back as a typed error: they are printed,
/// either interpolated into a message or through `localizedDescription`. Both renderings are
/// taken where the error was caught, and this stands in for the original.
public struct CapturedBuildError: Error, LocalizedError, CustomStringConvertible, Sendable {
    /// What `String(describing:)` gave for the original error.
    public let description: String
    /// What `localizedDescription` gave for it.
    public let localizedMessage: String

    public init(_ error: any Error) {
        self.description = String(describing: error)
        self.localizedMessage = error.localizedDescription
    }

    /// Makes `localizedDescription` return the original's, rather than a description of this.
    public var errorDescription: String? { localizedMessage }
}

// Build error information
public struct BuildErrorDetail: Sendable {
    public let file: String
    public let stage: BuildStage
    public let error: CapturedBuildError
    public let recoverable: Bool
    
    public init(file: String, stage: BuildStage, error: any Error, recoverable: Bool) {
        self.file = file
        self.stage = stage
        self.error = CapturedBuildError(error)
        self.recoverable = recoverable
    }
}

// Build stages
public enum BuildStage: Sendable {
    case parsing
    case rendering
    case writing
    case unknown
}

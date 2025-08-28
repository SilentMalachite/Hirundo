import Foundation

/// I/O操作のタイムアウト設定
public struct TimeoutConfig: Codable, Sendable {
    public let fileReadTimeout: TimeInterval
    public let fileWriteTimeout: TimeInterval
    public let directoryOperationTimeout: TimeInterval
    public let httpRequestTimeout: TimeInterval
    public let fsEventsTimeout: TimeInterval
    public let serverStartTimeout: TimeInterval
    
    public init(
        fileReadTimeout: TimeInterval = 30.0,
        fileWriteTimeout: TimeInterval = 30.0,
        directoryOperationTimeout: TimeInterval = 15.0,
        httpRequestTimeout: TimeInterval = 10.0,
        fsEventsTimeout: TimeInterval = 5.0,
        serverStartTimeout: TimeInterval = 30.0
    ) throws {
        // タイムアウト値の検証（簡素化）
        let timeouts = [
            ("fileReadTimeout", fileReadTimeout),
            ("fileWriteTimeout", fileWriteTimeout),
            ("directoryOperationTimeout", directoryOperationTimeout),
            ("httpRequestTimeout", httpRequestTimeout),
            ("fsEventsTimeout", fsEventsTimeout),
            ("serverStartTimeout", serverStartTimeout)
        ]
        
        for (name, value) in timeouts {
            let validatedValue = try ConfigValidation.validateTimeout(value, fieldName: name)
            switch name {
            case "fileReadTimeout":
                self.fileReadTimeout = validatedValue
            case "fileWriteTimeout":
                self.fileWriteTimeout = validatedValue
            case "directoryOperationTimeout":
                self.directoryOperationTimeout = validatedValue
            case "httpRequestTimeout":
                self.httpRequestTimeout = validatedValue
            case "fsEventsTimeout":
                self.fsEventsTimeout = validatedValue
            case "serverStartTimeout":
                self.serverStartTimeout = validatedValue
            default:
                break
            }
        }
    }
    
    /// デフォルトのタイムアウト設定を作成
    public static func defaultTimeout() -> TimeoutConfig {
        do {
            return try TimeoutConfig()
        } catch {
            return TimeoutConfig(
                fileReadTimeout: 30.0,
                fileWriteTimeout: 30.0,
                directoryOperationTimeout: 15.0,
                httpRequestTimeout: 10.0,
                fsEventsTimeout: 5.0,
                serverStartTimeout: 30.0,
                skipValidation: true
            )
        }
    }
    
    /// 内部イニシャライザ（検証スキップ）
    private init(
        fileReadTimeout: TimeInterval,
        fileWriteTimeout: TimeInterval,
        directoryOperationTimeout: TimeInterval,
        httpRequestTimeout: TimeInterval,
        fsEventsTimeout: TimeInterval,
        serverStartTimeout: TimeInterval,
        skipValidation: Bool
    ) {
        self.fileReadTimeout = fileReadTimeout
        self.fileWriteTimeout = fileWriteTimeout
        self.directoryOperationTimeout = directoryOperationTimeout
        self.httpRequestTimeout = httpRequestTimeout
        self.fsEventsTimeout = fsEventsTimeout
        self.serverStartTimeout = serverStartTimeout
    }
}
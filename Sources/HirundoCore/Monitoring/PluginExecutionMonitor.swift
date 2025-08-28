import Foundation

/// プラグイン実行の監視を行うクラス
public class PluginExecutionMonitor {
    private var startTime: Date?
    private var memoryBaseline: Int = 0
    public var fileOperationCount: Int = 0
    
    public init() {}
    
    /// 監視を開始
    public func startMonitoring() {
        startTime = Date()
        memoryBaseline = getCurrentMemoryUsage()
        fileOperationCount = 0
    }
    
    /// リソース制限をチェック
    /// - Parameter limits: プラグインリソース制限
    /// - Throws: PluginResourceLimitError 制限を超えた場合
    public func checkResourceLimits(_ limits: PluginResourceLimits) throws {
        // CPU時間をチェック
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > limits.cpuTimeLimit {
                throw PluginResourceLimitError.cpuTimeLimitExceeded(limits.cpuTimeLimit)
            }
        }
        
        // メモリ使用量をチェック
        let currentMemory = getCurrentMemoryUsage()
        let memoryUsed = currentMemory - memoryBaseline
        if memoryUsed > limits.memoryLimit {
            throw PluginResourceLimitError.memoryLimitExceeded(memoryUsed, limits.memoryLimit)
        }
        
        // ファイル操作をチェック
        if fileOperationCount > limits.fileOperationLimit {
            throw PluginResourceLimitError.fileLimitExceeded(limits.fileOperationLimit)
        }
    }
    
    /// ファイル操作カウントを増加
    public func incrementFileOperations() {
        fileOperationCount += 1
    }
    
    /// 現在のメモリ使用量を取得
    private func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}
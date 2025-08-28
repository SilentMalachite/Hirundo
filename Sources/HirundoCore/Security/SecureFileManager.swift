import Foundation

/// プラグインサンドボックス用のセキュアファイルマネージャー
public class SecureFileManager {
    private let allowedDirectories: [String]
    private let projectPath: String
    private let deniedPaths: Set<String> = [
        "/etc/passwd",
        "/etc/shadow",
        "/System",
        "/usr/bin",
        "/usr/sbin",
        "/bin",
        "/sbin",
        "~/.ssh",
        "~/.aws",
        "~/.config"
    ]
    
    public init(allowedDirectories: [String], projectPath: String) {
        self.allowedDirectories = allowedDirectories
        self.projectPath = projectPath
    }
    
    /// ファイルアクセスをチェック
    /// - Parameter path: チェックするファイルパス
    /// - Throws: PluginSecurityError アクセスが拒否された場合
    public func checkFileAccess(_ path: String) throws {
        let normalizedPath = URL(fileURLWithPath: path).standardized.path
        
        // 拒否されたパスを最初にチェック
        for deniedPath in deniedPaths {
            let expandedPath = (deniedPath as NSString).expandingTildeInPath
            if normalizedPath.hasPrefix(expandedPath) {
                throw PluginSecurityError.unauthorizedFileAccess(path)
            }
        }
        
        // シンボリックリンク攻撃を防ぐためのシンボリックリンクチェック
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let fileType = attributes[.type] as? FileAttributeType,
           fileType == .typeSymbolicLink {
            // シンボリックリンクを解決して宛先をチェック
            let resolvedPath = try FileManager.default.destinationOfSymbolicLink(atPath: path)
            try checkFileAccess(resolvedPath)
            return
        }
        
        // プロジェクトディレクトリ内のアクセスは常に許可
        if normalizedPath.hasPrefix(projectPath) {
            return
        }
        
        // パスが許可されたディレクトリ内にあるかチェック
        let isAllowed = allowedDirectories.contains { allowedDir in
            normalizedPath.hasPrefix(allowedDir)
        }
        
        if !isAllowed {
            throw PluginSecurityError.unauthorizedFileAccess(path)
        }
    }
    
    /// サンドボックス化されたファイル読み込み（完全な検証付き）
    /// - Parameter path: 読み込むファイルパス
    /// - Returns: ファイルデータ
    /// - Throws: PluginSecurityError アクセスが拒否された場合
    public func readFile(at path: String) throws -> Data {
        try checkFileAccess(path)
        
        // FileSecurityUtilitiesを使用した追加の検証
        let validatedPath = try FileSecurityUtilities.validatePath(
            path,
            allowSymlinks: false,
            basePath: projectPath
        )
        
        // サイズ制限付きで読み込み
        let attributes = try FileManager.default.attributesOfItem(atPath: validatedPath)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        guard fileSize <= 50_000_000 else { // プラグインファイル読み込み用50MB制限
            throw PluginSecurityError.fileTooLarge(path, fileSize)
        }
        
        return try Data(contentsOf: URL(fileURLWithPath: validatedPath))
    }
    
    /// ファイル書き込み
    /// - Parameters:
    ///   - data: 書き込むデータ
    ///   - path: 書き込み先パス
    /// - Throws: PluginSecurityError アクセスが拒否された場合
    public func writeFile(_ data: Data, to path: String) throws {
        try checkFileAccess(path)
        
        // 書き込みサイズ制限
        guard data.count <= 10_000_000 else { // プラグインファイル書き込み用10MB制限
            throw PluginSecurityError.writeTooLarge(path, data.count)
        }
        
        // 安全な書き込みのためにFileSecurityUtilitiesを使用
        try FileSecurityUtilities.writeData(
            data,
            toPath: path,
            basePath: projectPath
        )
    }
    
    /// ファイルの存在確認
    /// - Parameter path: 確認するファイルパス
    /// - Returns: ファイルが存在するかどうか
    public func fileExists(at path: String) -> Bool {
        do {
            try checkFileAccess(path)
            return FileManager.default.fileExists(atPath: path)
        } catch {
            return false
        }
    }
    
    /// ディレクトリの存在確認
    /// - Parameter path: 確認するディレクトリパス
    /// - Returns: ディレクトリが存在するかどうか
    public func directoryExists(at path: String) -> Bool {
        do {
            try checkFileAccess(path)
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        } catch {
            return false
        }
    }
    
    /// ディレクトリの内容を一覧表示
    /// - Parameter path: 一覧表示するディレクトリパス
    /// - Returns: ディレクトリ内容の配列
    /// - Throws: PluginSecurityError アクセスが拒否された場合
    public func contentsOfDirectory(at path: String) throws -> [String] {
        try checkFileAccess(path)
        
        let validatedPath = try FileSecurityUtilities.validatePath(
            path,
            allowSymlinks: false,
            basePath: projectPath
        )
        
        return try FileManager.default.contentsOfDirectory(atPath: validatedPath)
    }
    
    /// ディレクトリを作成
    /// - Parameter path: 作成するディレクトリパス
    /// - Throws: PluginSecurityError アクセスが拒否された場合
    public func createDirectory(at path: String) throws {
        try checkFileAccess(path)
        
        let validatedPath = try FileSecurityUtilities.validatePath(
            path,
            allowSymlinks: false,
            basePath: projectPath
        )
        
        try FileManager.default.createDirectory(
            atPath: validatedPath,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    /// ファイルを削除
    /// - Parameter path: 削除するファイルパス
    /// - Throws: PluginSecurityError アクセスが拒否された場合
    public func removeFile(at path: String) throws {
        try checkFileAccess(path)
        
        let validatedPath = try FileSecurityUtilities.validatePath(
            path,
            allowSymlinks: false,
            basePath: projectPath
        )
        
        try FileManager.default.removeItem(atPath: validatedPath)
    }
}
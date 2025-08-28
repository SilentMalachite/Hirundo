import Foundation

/// 設定値の検証を行うユーティリティ
public struct ConfigValidation {
    
    /// 文字列が空でないことを検証
    public static func validateNonEmpty(_ value: String, fieldName: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConfigError.invalidValue("\(fieldName) cannot be empty")
        }
        return trimmed
    }
    
    /// 文字列の長さを検証
    public static func validateLength(_ value: String, maxLength: Int, fieldName: String) throws -> String {
        guard value.count <= maxLength else {
            throw ConfigError.invalidValue("\(fieldName) cannot exceed \(maxLength) characters")
        }
        return value
    }
    
    /// 文字列が空でないことを検証し、長さもチェック
    public static func validateNonEmptyAndLength(_ value: String, maxLength: Int, fieldName: String) throws -> String {
        let trimmed = try validateNonEmpty(value, fieldName: fieldName)
        return try validateLength(trimmed, maxLength: maxLength, fieldName: fieldName)
    }
    
    /// オプショナル文字列の長さを検証
    public static func validateOptionalLength(_ value: String?, maxLength: Int, fieldName: String) throws -> String? {
        guard let value = value else { return nil }
        return try validateLength(value, maxLength: maxLength, fieldName: fieldName)
    }
    
    /// オプショナル文字列をトリム
    public static func trimOptional(_ value: String?) -> String? {
        return value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// メールアドレスの形式を検証
    public static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    /// URLの形式を検証
    public static func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    /// 言語コードの形式を検証（簡素化）
    public static func isValidLanguageCode(_ language: String) -> Bool {
        // 基本的な言語コード形式をチェック（例: en, en-US, ja-JP）
        let languageRegex = "^[a-z]{2}(-[A-Z]{2})?$"
        let languagePredicate = NSPredicate(format: "SELF MATCHES[c] %@", languageRegex)
        return languagePredicate.evaluate(with: language)
    }
    
    /// ポート番号を検証
    public static func validatePort(_ port: Int) throws -> Int {
        guard port > 0 && port <= 65535 else {
            throw ConfigError.invalidValue("Port must be between 1 and 65535")
        }
        return port
    }
    
    /// 正の整数を検証
    public static func validatePositiveInt(_ value: Int, fieldName: String) throws -> Int {
        guard value > 0 else {
            throw ConfigError.invalidValue("\(fieldName) must be a positive integer")
        }
        return value
    }
    
    /// 非負の整数を検証
    public static func validateNonNegativeInt(_ value: Int, fieldName: String) throws -> Int {
        guard value >= 0 else {
            throw ConfigError.invalidValue("\(fieldName) must be a non-negative integer")
        }
        return value
    }
    
    /// タイムアウト値を検証（0.1秒から600秒の範囲）
    public static func validateTimeout(_ value: Double, fieldName: String) throws -> Double {
        guard value >= 0.1 && value <= 600.0 else {
            throw ConfigError.invalidValue("\(fieldName) must be between 0.1 and 600.0 seconds")
        }
        return value
    }
}
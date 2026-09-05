import Foundation

/// サイトの著者情報
public struct Author: Codable, Sendable {
    public let name: String
    public let email: String?
    
    public init(name: String, email: String? = nil) throws {
        // 名前の検証（簡素化）
        self.name = try ConfigValidation.validateNonEmptyAndLength(name, maxLength: 100, fieldName: "Author name")
        
        // メールアドレスの検証（簡素化）
        if let email = email {
            let trimmedEmail = try ConfigValidation.validateLength(email, maxLength: 254, fieldName: "Email")
            guard ConfigValidation.isValidEmail(trimmedEmail) else {
                throw ConfigError.invalidValue("Invalid email format: \(trimmedEmail)")
            }
            self.email = trimmedEmail
        } else {
            self.email = nil
        }
    }
    
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, email
    }
    
    /// Routes decoding through the throwing initializer above, which the synthesized decoder
    /// would otherwise bypass — leaving the e-mail format and length rules unenforced.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(String.self, forKey: .name),
            email: container.decodeIfPresent(String.self, forKey: .email)
        )
    }
}
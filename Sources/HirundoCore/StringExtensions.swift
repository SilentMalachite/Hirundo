import Foundation

extension String {
    func slugify(maxLength: Int = 100) -> String {
        // Step 1: Convert to lowercase and trim
        var slug = self.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Step 2: Replace spaces and common separators with hyphens
        slug = slug.replacingOccurrences(of: #"[\s\-_\+]+"#, with: "-", options: .regularExpression)
        
        // Step 3: Remove or replace dangerous characters for URLs
        // Keep letters (including Unicode), numbers, and hyphens
        // Remove only truly problematic characters for URLs
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        slug = slug.unicodeScalars.compactMap { scalar in
            if allowedCharacters.contains(scalar) {
                return String(scalar)
            } else if scalar.value == 0x20 || scalar.value == 0x5F { // space or underscore
                return "-"
            } else if scalar.properties.isAlphabetic || CharacterSet.decimalDigits.contains(scalar) {
                // Keep Unicode letters and numbers (Japanese, Chinese, etc.)
                return String(scalar)
            } else {
                return nil
            }
        }.joined()
        
        // Step 4: Handle multiple consecutive hyphens
        slug = slug.replacingOccurrences(of: #"\-+"#, with: "-", options: .regularExpression)
        
        // Step 5: Remove leading and trailing hyphens
        slug = slug.replacingOccurrences(of: #"^-+|-+$"#, with: "", options: .regularExpression)
        
        // Step 6: Ensure slug is not empty
        if slug.isEmpty {
            slug = "untitled"
        }
        
        // Step 7: Limit length if needed
        if slug.count > maxLength {
            let endIndex = slug.index(slug.startIndex, offsetBy: maxLength)
            slug = String(slug[..<endIndex])
            
            // Make sure we don't end with a hyphen after truncation
            slug = slug.replacingOccurrences(of: #"-+$"#, with: "", options: .regularExpression)
        }
        
        return slug
    }
    
    func padLeft(toLength: Int, withPad character: Character) -> String {
        let stringLength = self.count
        if stringLength < toLength {
            return String(repeating: character, count: toLength - stringLength) + self
        } else {
            return self
        }
    }
}
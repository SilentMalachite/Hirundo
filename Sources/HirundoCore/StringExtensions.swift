import Foundation

extension String {
    func slugify(maxLength: Int = 100) -> String {
        // Use percent-encoding for URL-safe slugs, which is more robust for Unicode.
        let slug = self.lowercased()
            .replacingOccurrences(of: " ", with: "-")

        // Define a conservative ASCII-only allowed set for slug output
        // to ensure non-ASCII (e.g., Japanese) characters are percent-encoded.
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        
        var encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? slug
        // Normalize percent-encoding to use UPPERCASE hex without altering ASCII letters
        encodedSlug = encodedSlug.uppercasingPercentEscapes()
        
        // Truncate after encoding if necessary
        if encodedSlug.count > maxLength {
            let endIndex = encodedSlug.index(encodedSlug.startIndex, offsetBy: maxLength)
            let truncated = String(encodedSlug[..<endIndex])
            // Ensure we don't end with a hyphen or a partial encoding
            return truncated.trimmingCharacters(in: CharacterSet(charactersIn: "-%"))
        }
        
        if encodedSlug.isEmpty {
            return "untitled"
        }
        
        return encodedSlug
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

private extension String {
    func uppercasingPercentEscapes() -> String {
        var result = String()
        result.reserveCapacity(self.count)
        var i = self.startIndex
        while i < self.endIndex {
            let ch = self[i]
            if ch == "%" {
                let next1 = self.index(after: i)
                if next1 < self.endIndex {
                    let next2 = self.index(after: next1)
                    if next2 < self.endIndex {
                        let hex = self[next1...next2]
                        result.append("%")
                        result.append(contentsOf: hex.uppercased())
                        i = self.index(after: next2)
                        continue
                    }
                }
            }
            result.append(ch)
            i = self.index(after: i)
        }
        return result
    }
}

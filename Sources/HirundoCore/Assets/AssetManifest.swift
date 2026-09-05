import Foundation

/// static ディレクトリからの相対パスを、ビルドが実際に書いた出力ディレクトリからの相対パスに
/// 対応づける。
///
/// 両辺とも相対パスで、区切りは常に `/`。フィンガープリントが無効なときはすべての値がキーと
/// 等しくなるが、マニフェストは省略せず全アセットを載せる。参照の書き換えと古い出力の掃除は
/// どちらも「マニフェストが static の出力の完全な目録である」ことに依存している。
public struct AssetManifest: Equatable, Codable {
    private var entries: [String: String]

    public init(_ entries: [String: String] = [:]) {
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        entries = try [String: String](from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try entries.encode(to: encoder)
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// 出力ディレクトリからの相対パスの集合。掃除の「残すもの」の判定に使う。
    public var outputPaths: Set<String> { Set(entries.values) }

    public var dictionary: [String: String] { entries }

    public subscript(key: String) -> String? {
        get { entries[key] }
        set { entries[key] = newValue }
    }

    /// `directory`（出力ディレクトリからの相対ディレクトリ、ルート直下なら空文字列）にある
    /// ファイルの中で見つかった参照を書き換える。
    ///
    /// 書き換えないときは `nil` を返す。呼び出し側は元の文字列をそのまま残すこと。外部 URL、
    /// マニフェストに無い参照、値がキーと等しい参照はすべて `nil` になる。
    public func rewrite(reference: String, inDirectory directory: String) -> String? {
        let (path, suffix) = Self.splitSuffix(reference)
        guard !path.isEmpty else { return nil }
        guard !path.hasPrefix("//"), !Self.hasScheme(path) else { return nil }

        let isRootRelative = path.hasPrefix("/")
        let candidate = isRootRelative
            ? String(path.dropFirst())
            : (directory.isEmpty ? path : directory + "/" + path)

        guard let key = Self.normalize(candidate),
              let value = entries[key],
              value != key else { return nil }

        if isRootRelative {
            return "/" + value + suffix
        }
        return Self.relativePath(from: directory, to: value) + suffix
    }

    /// 相対パスの親ディレクトリ。ルート直下なら空文字列。
    public static func parentDirectory(of relativePath: String) -> String {
        var components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return "" }
        components.removeLast()
        return components.joined(separator: "/")
    }

    // MARK: - Private

    /// `a.css?v=1#x` を `("a.css", "?v=1#x")` に分ける。
    private static func splitSuffix(_ reference: String) -> (path: String, suffix: String) {
        guard let index = reference.firstIndex(where: { $0 == "?" || $0 == "#" }) else {
            return (reference, "")
        }
        return (String(reference[reference.startIndex..<index]), String(reference[index...]))
    }

    /// 最初の `/` `?` `#` より前に `:` が現れ、その前が正しいスキーム名になっているか。
    private static func hasScheme(_ path: String) -> Bool {
        for (offset, character) in path.enumerated() {
            if character == ":" { return offset > 0 }
            if character == "/" || character == "?" || character == "#" { return false }
            if offset == 0 {
                if !character.isLetter { return false }
            } else if !(character.isLetter || character.isNumber
                        || character == "+" || character == "-" || character == ".") {
                return false
            }
        }
        return false
    }

    /// `.` と `..` を解決する。出力ルートの外に出る場合は `nil`。
    private static func normalize(_ path: String) -> String? {
        var stack: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if stack.isEmpty { return nil }
                stack.removeLast()
            default:
                stack.append(String(component))
            }
        }
        return stack.isEmpty ? nil : stack.joined(separator: "/")
    }

    /// `directory` から `target` への相対パス。どちらも出力ディレクトリからの相対。
    private static func relativePath(from directory: String, to target: String) -> String {
        let from = directory.split(separator: "/").map(String.init)
        let to = target.split(separator: "/").map(String.init)
        var common = 0
        while common < from.count, common < to.count, from[common] == to[common] {
            common += 1
        }
        let ups = Array(repeating: "..", count: from.count - common)
        return (ups + to[common...]).joined(separator: "/")
    }
}

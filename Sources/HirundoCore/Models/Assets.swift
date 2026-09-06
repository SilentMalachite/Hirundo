import Foundation

/// アセット処理に関する設定（現時点ではフィンガープリント除外パターンのみ）。
public struct Assets: Codable, Sendable, Equatable {
    /// フィンガープリント（コンテンツハッシュ付きファイル名への変更）から除外する追加パターン。
    ///
    /// `AssetFingerprintExclusions` が持つ組み込みパターン（`robots.txt` など）に追加される
    /// だけで、組み込みパターンを取り除くことはできない。
    public var fingerprintExclude: [String]

    public init(fingerprintExclude: [String] = []) {
        self.fingerprintExclude = fingerprintExclude
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case fingerprintExclude
    }

    /// `fingerprintExclude` を独立して既定値（空配列）にデコードする。
    ///
    /// 合成されたデコーダーはすべてのキーを要求するため、`assets: {}` のようにキーを
    /// 1つも持たないブロックがあるだけで設定全体のパースが失敗してしまう。`features` や
    /// `build` など他の任意ブロックと同じく、欠けているキーには既定値を補う。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fingerprintExclude = try container.decodeIfPresent([String].self, forKey: .fingerprintExclude) ?? []
    }
}

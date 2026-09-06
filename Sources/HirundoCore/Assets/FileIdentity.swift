import Foundation

/// ファイルの識別情報。「判定したときと同じファイルをコピーしたか」を後から確かめるために持つ。
///
/// `AssetPipeline` はソースの閉じ込め判定とコピーを別々の `FileManager` 呼び出しで行うため、
/// その間にファイルが差し替えられたり書き換えられたりしても、それだけでは気づけない。
/// 判定の直後にこれを取り、コピーの直後にもう一度取って比べる。デバイス番号と inode が同じで、
/// サイズと更新時刻も同じなら、同じファイルの同じ内容を見ていたと判断する。
///
/// これは競合の窓を「判定から stat まで」の数マイクロ秒に狭めるものであって、ゼロにはしない。
/// ゼロにするにはファイル記述子で対象を固定して `fstat` する必要があるが、`copyItem` は
/// パスしか受け取らず、それを捨てるとパーミッション・拡張属性・APFS クローンも失う。
struct FileIdentity: Equatable {
    let device: Int
    let inode: Int
    let size: Int
    let modificationDate: Date

    /// `attributesOfItem` は `lstat` 相当でリンクを辿らない。渡すパスは解決済みであること。
    init(ofItemAtPath path: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        device = (attributes[.systemNumber] as? NSNumber)?.intValue ?? -1
        inode = (attributes[.systemFileNumber] as? NSNumber)?.intValue ?? -1
        size = (attributes[.size] as? NSNumber)?.intValue ?? -1
        modificationDate = (attributes[.modificationDate] as? Date) ?? .distantPast
    }
}

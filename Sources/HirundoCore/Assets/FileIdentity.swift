import Foundation

/// ファイルの識別情報。「判定したときと同じファイルをコピーしたか」を後から確かめるために持つ。
///
/// `AssetPipeline` はソースの閉じ込め判定とコピーを別々の `FileManager` 呼び出しで行うため、
/// その間にファイルが差し替えられたり書き換えられたりしても、それだけでは気づけない。
/// 判定の直後にこれを取り、コピーの直後にもう一度取って比べる。デバイス番号と inode が同じで、
/// サイズと更新時刻も同じなら、同じファイルの同じ内容を見ていたと判断する。
///
/// これは「変わっていたら気づく」ための仕掛けであって、競合そのものを塞ぐものではない。
/// 判定からコピー後の `stat` までの窓は `copyItem` を丸ごと含むので、大きなアセットでは
/// マイクロ秒ではなく秒の単位になる。そのうえで、`static/` の中に書き込める攻撃者は、
/// コピーの前後で元のパスとメタデータを復元するか、inode・サイズ・更新時刻を変えないまま
/// その場で書き換えることで、検出をすり抜けられる。塞ぐにはファイル記述子で対象を固定して
/// `fstat` する必要があるが、`copyItem` はパスしか受け取らず、それを捨てると
/// パーミッション・拡張属性・APFS クローンも失う。
///
/// 検出漏れはもう一つある。同サイズ・同 inode の上書きは更新時刻だけが手掛かりなので、
/// mtime の分解能が粗いボリューム（HFS+ や一部のネットワークマウントは1秒）では、同じ秒の
/// うちに書き換えられると検出できない。いずれの場合も、ハッシュを取るのはコピー済みの
/// ステージングファイルなので、「ハッシュは実際に書き出すバイト列を覆う」という不変条件は
/// 影響を受けない。壊れるのは検出であって、出力名と中身の対応ではない。
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

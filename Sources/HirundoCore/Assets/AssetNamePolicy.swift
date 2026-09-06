import Foundation

/// フィンガープリントを付けてはいけないアセットの判定。
///
/// フィンガープリントは「参照を書き換えられる」ことを前提にしている。HTML や CSS から
/// `href` / `src` / `url(...)` で参照されるアセットはそれで足りるが、**固定の URL で外部から
/// 取得されるファイル**は参照元が存在しないので書き換えようがない。名前を変えた時点で
/// 取得できなくなる。
///
/// ここで挙げるのはその契約が名前そのものに埋まっているファイルだけで、いずれも元の名前で
/// 出力され、マニフェストの値はキーと等しくなる。
public enum AssetNamePolicy {

    /// 出力ルート直下にあるときだけ固定 URL の契約を持つ名前。
    ///
    /// - `robots.txt` / `sitemap.xml`: クローラが `/robots.txt` を直接取得する
    /// - `favicon.ico`: 参照が無くてもブラウザが `/favicon.ico` を取得する
    /// - `CNAME`: GitHub Pages のカスタムドメイン
    /// - `_redirects` / `_headers`: Netlify・Cloudflare Pages のホスティング設定
    /// - `ads.txt` / `app-ads.txt`: IAB の仕様でルート直下と決まっている
    /// - `sw.js` / `service-worker.js`: JavaScript 内の固定 URL で登録され、
    ///   制御できる範囲（スコープ）がそのパスで決まる
    private static let fixedRootNames: Set<String> = [
        "robots.txt",
        "sitemap.xml",
        "favicon.ico",
        "CNAME",
        "_redirects",
        "_headers",
        "ads.txt",
        "app-ads.txt",
        "sw.js",
        "service-worker.js"
    ]

    /// 中身が固定 URL で参照されるディレクトリ。深さは問わない。
    private static let fixedDirectories: Set<String> = [".well-known"]

    /// `static/` からの相対パスが、元の名前のまま出力されなければならないアセットか。
    ///
    /// 照合は綴りどおり（大文字小文字を区別する）。`Robots.txt` は `/robots.txt` として
    /// 取得されるわけではないので、通常のアセットとして扱う。
    public static func requiresStableName(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let first = components.first else { return false }

        if fixedDirectories.contains(first) {
            return true
        }
        return components.count == 1 && fixedRootNames.contains(first)
    }
}

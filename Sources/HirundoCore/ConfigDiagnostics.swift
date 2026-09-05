import Foundation
import Yams

/// Configuration checks that go beyond "does it decode".
///
/// The decoder ignores keys it does not recognize, so a misspelled key — or a block that was
/// never wired up, like `timeouts` — behaves exactly like not writing it at all. That silence is
/// what `hirundo validate` exists to break.
public enum ConfigDiagnostics {
    public struct Report {
        /// The configuration as the rest of Hirundo will see it.
        public let config: HirundoConfig
        /// Problems that do not stop a build but almost certainly are not what the user meant.
        public let warnings: [String]

        public init(config: HirundoConfig, warnings: [String]) {
            self.config = config
            self.warnings = warnings
        }
    }

    /// The keys the decoder acts on, derived from the models' own `CodingKeys` so that this
    /// cannot drift away from what is actually decoded.
    public static let recognizedTopLevelKeys: [String] =
        HirundoConfig.CodingKeys.allCases.map { $0.rawValue }.sorted()

    private static let recognizedKeysByBlock: [String: Set<String>] = [
        HirundoConfig.CodingKeys.site.rawValue: keys(of: Site.CodingKeys.self),
        HirundoConfig.CodingKeys.build.rawValue: keys(of: Build.CodingKeys.self),
        HirundoConfig.CodingKeys.server.rawValue: keys(of: Server.CodingKeys.self),
        HirundoConfig.CodingKeys.blog.rawValue: keys(of: Blog.CodingKeys.self),
        HirundoConfig.CodingKeys.features.rawValue: keys(of: Features.CodingKeys.self),
        HirundoConfig.CodingKeys.limits.rawValue: keys(of: Limits.CodingKeys.self)
    ]

    private static func keys<K: CodingKey & CaseIterable>(of _: K.Type) -> Set<String> {
        return Set(K.allCases.map { $0.stringValue })
    }

    /// " Did you mean 'sitemap'?" for a key that is one or two edits away from a real one.
    ///
    /// A misspelling is the common case, and naming the intended key is far more use than
    /// listing every key that would have been legal. Keys the configuration already sets are
    /// excluded — suggesting one of those would be advice to write a duplicate. Ties break
    /// alphabetically so that the same file always produces the same message.
    private static func suggestion(
        for key: String,
        among candidates: Set<String>,
        alreadyUsed: Set<String>
    ) -> String {
        let threshold = key.count <= 4 ? 1 : 2
        let best = candidates
            .subtracting(alreadyUsed)
            .map { (candidate: $0, distance: editDistance(key.lowercased(), $0.lowercased())) }
            .filter { $0.distance <= threshold }
            .min { ($0.distance, $0.candidate) < ($1.distance, $1.candidate) }
        return best.map { " Did you mean '\($0.candidate)'?" } ?? ""
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            previous = current
        }
        return previous[b.count]
    }

    public static func inspect(yaml: String) throws -> Report {
        let config = try HirundoConfig.parse(from: yaml)
        return Report(config: config, warnings: unrecognizedKeyWarnings(in: yaml))
    }

    public static func inspect(fileAt url: URL) throws -> Report {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.fileNotFound(url.path)
        }
        let yaml: String
        do {
            yaml = try HirundoConfig.readConfigFile(at: url)
        } catch let error as ConfigError {
            throw error
        } catch {
            // Matches `HirundoConfig.load`, so a read failure is still a configuration error and
            // gets the same framing from the CLI.
            throw ConfigError.parseError(error.localizedDescription)
        }
        return try inspect(yaml: yaml)
    }

    /// Reports keys at the top level and one level in — the two places a Hirundo configuration
    /// actually has keys. Anything deeper (`site.author`) is left alone.
    ///
    /// Only reached after `parse` has succeeded, so the document is known to be a mapping.
    private static func unrecognizedKeyWarnings(in yaml: String) -> [String] {
        guard let root = (try? Yams.load(yaml: yaml)) as? [String: Any] else {
            // Fail closed: saying nothing here would be indistinguishable from "no problems".
            return ["Could not re-read the configuration to check for unrecognized keys."]
        }

        let recognized = Set(recognizedTopLevelKeys)
        let presentTopLevel = Set(root.keys)
        var warnings: [String] = []

        for key in root.keys.sorted() {
            guard recognized.contains(key) else {
                warnings.append(
                    "Unknown top-level key '\(key)' — it is ignored."
                        + suggestion(for: key, among: recognized, alreadyUsed: presentTopLevel)
                )
                continue
            }
            guard
                let block = root[key] as? [String: Any],
                let recognizedChildren = recognizedKeysByBlock[key]
            else {
                continue
            }
            let presentChildren = Set(block.keys)
            for child in block.keys.sorted() where !recognizedChildren.contains(child) {
                warnings.append(
                    "Unknown key '\(key).\(child)' — it is ignored."
                        + suggestion(
                            for: child,
                            among: recognizedChildren,
                            alreadyUsed: presentChildren
                        )
                )
            }
        }

        return warnings
    }
}

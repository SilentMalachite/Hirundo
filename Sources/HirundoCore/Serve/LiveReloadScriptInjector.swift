import Foundation

/// Inserts the live-reload client into an HTML page before it is served.
///
/// The development server rewrites every HTML response on the fly rather than requiring the
/// project to add a `<script>` tag itself — a static site generator's whole point is that the
/// output is exactly what a production host would serve, so nothing in `content/` or
/// `templates/` should know that live reload exists. Injection has to be resilient to whatever
/// shape a template author's HTML takes: missing `<body>` closing tags, uppercase tags copied
/// from an old boilerplate, or (rarely) more than one `</body>` in a malformed page. In every
/// case the goal is the same — get the script running in the browser without disturbing content
/// the author wrote, which is why we insert immediately before the tag rather than replacing it.
public struct LiveReloadScriptInjector: Sendable {
    private let endpointPath: String

    public init(endpointPath: String = "/livereload") {
        self.endpointPath = endpointPath
    }

    /// Returns `html` with the live-reload client inserted just before the last `</body>`
    /// (case-insensitively), or appended to the end if no `</body>` is present.
    public func inject(into html: String) -> String {
        let script = Self.scriptFragment(endpointPath: endpointPath)
        if let range = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            var result = html
            result.insert(contentsOf: script, at: range.lowerBound)
            return result
        }
        return html + script
    }

    /// Builds the `<script>` fragment. Wrapped in leading/trailing newlines so it never merges
    /// with whatever line of HTML it lands next to, and the script body is an IIFE so it leaves
    /// no names behind in the page's global scope.
    private static func scriptFragment(endpointPath: String) -> String {
        let javascript = """
        (function () {
          var reconnectDelay = 500;
          var maxReconnectDelay = 10000;

          function connect() {
            var socket = new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + "\(endpointPath)");

            socket.onopen = function () {
              // A successful connection means the server is reachable again; forget any
              // backoff we accumulated while it was down.
              reconnectDelay = 500;
            };

            socket.onmessage = function (event) {
              if (event.data === "reload") {
                location.reload();
              }
            };

            socket.onclose = function () {
              setTimeout(connect, reconnectDelay);
              reconnectDelay = Math.min(reconnectDelay * 2, maxReconnectDelay);
            };

            socket.onerror = function () {
              // Let onclose own reconnection; closing here avoids scheduling it twice.
              socket.close();
            };
          }

          connect();
        })();
        """
        return "\n<script>\n\(javascript)\n</script>\n"
    }
}

import Foundation
import Network

@main
struct TestServerMain {
    static func main() async {
        let server = TestHTTPServer()
        let port: UInt16 = 8089

        do {
            let actualPort = try await server.start(preferredPort: port)
            print("🚀 Kodiz TestServer running on http://127.0.0.1:\(actualPort)")
            print("Available endpoints:")
            print("  /range?size=<bytes>        - 206 Partial Content + Content-Range + ETag")
            print("  /norange?size=<bytes>      - 200 OK without Accept-Ranges (ignores Range)")
            print("  /unknown-length            - Stream without Content-Length")
            print("  /ratelimit?limit=3         - 429 Retry-After, 503 if max_conns exceeded")
            print("  /flaky                     - Drops connection on odd attempts, succeeds on retries")
            print("  /slow?speed=51200          - Throttled speed (e.g. 50 KB/s)")
            print("  /etag-change               - Changes ETag on subsequent request, tests If-Range")
            print("  /redirect                  - 302 redirect chain to /range")
            print("  /gzip-force                - Forces gzip unless Accept-Encoding: identity is sent")
            print("  /disposition               - Returns RFC 5987 Türkçe dosya.zip")
            print("\nPress Ctrl+C to stop.")

            // Keep alive
            while true {
                try await Task.sleep(nanoseconds: 3_600_000_000_000)
            }
        } catch {
            print("❌ Failed to start TestServer: \(error)")
            exit(1)
        }
    }
}

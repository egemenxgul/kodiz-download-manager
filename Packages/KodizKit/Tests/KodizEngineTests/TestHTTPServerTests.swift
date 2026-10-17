import XCTest
import Foundation
@testable import KodizEngine

final class TestHTTPServerTests: XCTestCase {
    var server: TestHTTPServer!
    var serverPort: UInt16 = 0

    override func setUp() async throws {
        server = TestHTTPServer()
        serverPort = try await server.start(preferredPort: 0)
    }

    override func tearDown() async throws {
        server.stop()
        server = nil
    }

    func testDeterministicSHA256Consistency() {
        let size: Int64 = 1024 * 1024 // 1 MB
        let sha1 = DeterministicData.sha256(totalBytes: size)
        let sha2 = DeterministicData.sha256(totalBytes: size)
        XCTAssertEqual(sha1, sha2)
        XCTAssertFalse(sha1.isEmpty)

        let diffSeedSha = DeterministicData.sha256(totalBytes: size, seed: DeterministicData.changedSeed)
        XCTAssertNotEqual(sha1, diffSeedSha)
    }

    func testRangeProfile() async throws {
        let url = URL(string: "http://127.0.0.1:\(serverPort)/range?size=1048576")!
        var request = URLRequest(url: url)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("Not HTTPURLResponse")
            return
        }

        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 0-1023/1048576")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Accept-Ranges"), "bytes")
        XCTAssertEqual(http.value(forHTTPHeaderField: "ETag"), "\"kdm-test-etag\"")
        XCTAssertEqual(data.count, 1024)

        let expectedData = DeterministicData.generateChunk(offset: 0, count: 1024)
        XCTAssertEqual(data, expectedData)
    }

    func testNoRangeProfile() async throws {
        let url = URL(string: "http://127.0.0.1:\(serverPort)/norange?size=65536")!
        var request = URLRequest(url: url)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("Not HTTPURLResponse")
            return
        }

        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Accept-Ranges"), "none")
        XCTAssertEqual(data.count, 65536, "Server must ignore Range and return entire body")
    }

    func testUnknownLengthProfile() async throws {
        let url = URL(string: "http://127.0.0.1:\(serverPort)/unknown-length?size=32768")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else {
            XCTFail("Not HTTPURLResponse")
            return
        }

        XCTAssertEqual(http.statusCode, 200)
        XCTAssertNil(http.value(forHTTPHeaderField: "Content-Length"))
        XCTAssertEqual(data.count, 32768)
    }

    func testRateLimitProfile() async throws {
        let url = URL(string: "http://127.0.0.1:\(serverPort)/ratelimit?limit=2&size=1024")!

        // Attempt 1 -> 429
        var (_, resp) = try await URLSession.shared.data(for: URLRequest(url: url))
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 429)
        XCTAssertEqual((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"), "1")

        // Attempt 2 -> 429
        (_, resp) = try await URLSession.shared.data(for: URLRequest(url: url))
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 429)

        // Attempt 3 -> 200
        let (data, resp3) = try await URLSession.shared.data(for: URLRequest(url: url))
        XCTAssertEqual((resp3 as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data.count, 1024)
    }

    func testFlakyProfile() async throws {
        let url = URL(string: "http://127.0.0.1:\(serverPort)/flaky?size=262144")!
        var request = URLRequest(url: url)
        request.setValue("bytes=0-262143", forHTTPHeaderField: "Range")

        // 1st attempt: server drops connection midway
        do {
            _ = try await URLSession.shared.data(for: request)
            // If URLSession reads partial or throws:
        } catch {
            // Expected connection drop
        }

        // 2nd attempt: server succeeds on retry!
        let (data, resp) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(data.count, 262144)
    }

    func testRedirectProfile() async throws {
        let url = URL(string: "http://127.0.0.1:\(serverPort)/redirect?size=1024")!
        let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = resp as? HTTPURLResponse else {
            XCTFail("Not HTTPURLResponse")
            return
        }

        XCTAssertEqual(http.statusCode, 200)
        XCTAssertTrue(http.url?.path.contains("/range") == true)
        XCTAssertEqual(data.count, 1024)
    }

    func testGzipForceProfile() async throws {
        let url = URL(string: "http://127.0.0.1:\(serverPort)/gzip-force?size=10240")!

        // With identity
        var reqIdentity = URLRequest(url: url)
        reqIdentity.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (dataId, respId) = try await URLSession.shared.data(for: reqIdentity)
        XCTAssertNil((respId as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding"))
        XCTAssertEqual(dataId.count, 10240)

        // Without identity (gzip force)
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["Accept-Encoding": "gzip"]
        let customSession = URLSession(configuration: config)
        var reqGzip = URLRequest(url: url)
        reqGzip.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        let (dataGz, respGz) = try await customSession.data(for: reqGzip)
        // URLSession automatically decompresses gzip responses, but verifies decompressed size matches
        XCTAssertEqual(dataGz.count, 10240)
        _ = respGz
    }

    func testDispositionProfile() async throws {
        let url = URL(string: "http://127.0.0.1:\(serverPort)/disposition?size=1024")!
        let (_, resp) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = resp as? HTTPURLResponse else {
            XCTFail("Not HTTPURLResponse")
            return
        }

        let cd = http.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        XCTAssertTrue(cd.contains("UTF-8''T%C3%BCrk%C3%A7e%20dosya.zip"))
    }

    func testETagChangeProfile() async throws {
        let url = URL(string: "http://127.0.0.1:\(serverPort)/etag-change?size=1024")!

        // 1st request -> returns ETag "etag-v1"
        let (_, resp1) = try await URLSession.shared.data(for: URLRequest(url: url))
        XCTAssertEqual((resp1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"), "\"etag-v1\"")

        // 2nd request -> still "etag-v1" (changes after 2nd request)
        let (_, resp2) = try await URLSession.shared.data(for: URLRequest(url: url))
        XCTAssertEqual((resp2 as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"), "\"etag-v1\"")

        // 3rd request with If-Range: "etag-v1" -> server detects change to "etag-v2" and returns 200 OK + full body!
        var req3 = URLRequest(url: url)
        req3.setValue("bytes=500-1023", forHTTPHeaderField: "Range")
        req3.setValue("\"etag-v1\"", forHTTPHeaderField: "If-Range")

        let (data3, resp3) = try await URLSession.shared.data(for: req3)
        let http3 = resp3 as? HTTPURLResponse
        XCTAssertEqual(http3?.statusCode, 200, "If-Range mismatch must return 200 OK according to RFC 7233")
        XCTAssertEqual(http3?.value(forHTTPHeaderField: "ETag"), "\"etag-v2\"")
        XCTAssertEqual(data3.count, 1024, "Full body of new representation must be returned")
    }
}

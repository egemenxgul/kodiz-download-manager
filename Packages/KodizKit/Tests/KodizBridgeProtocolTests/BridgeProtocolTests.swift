import XCTest
@testable import KodizBridgeProtocol

private final class MockBridgeDelegate: BridgeServerDelegate, @unchecked Sendable {
    var delayNanoseconds: UInt64 = 0

    func handleBridgeMessage(_ message: BridgeMessage) async -> BridgeResponse {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return BridgeResponse(id: message.id, ok: true, downloadId: "test-dl-" + message.id)
    }
}

final class BridgeProtocolTests: XCTestCase {
    private var testSocketPath: String!
    private var testBaseDir: String!

    override func setUp() async throws {
        let unique = UUID().uuidString
        testBaseDir = "/tmp/kodiz-test/\(unique)"
        try FileManager.default.createDirectory(atPath: testBaseDir, withIntermediateDirectories: true)
        testSocketPath = "\(testBaseDir!)/test_bridge.sock"
    }

    override func tearDown() async throws {
        if let dir = testBaseDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
    }

    func testMessageFraming() {
        let sample = "{\"test\": true}".data(using: .utf8)!
        let framed = MessageFraming.encode(sample)

        XCTAssertEqual(framed.count, sample.count + 4)
        let decodedLength = MessageFraming.decodeHeader(from: framed)
        XCTAssertEqual(decodedLength, UInt32(sample.count))
    }

    func testBridgeMessageSerialization() throws {
        let cookie = BridgeCookie(name: "session", value: "abc123xyz", domain: ".example.com", path: "/", secure: true, httpOnly: true)
        let payload = BridgePayload(
            url: "https://example.com/file.dmg",
            referrer: "https://example.com",
            fileNameHint: "file.dmg",
            totalBytes: 104857600,
            cookies: [cookie]
        )
        let message = BridgeMessage(id: "msg-1", type: "download.add", browser: "chrome", payload: payload)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(BridgeMessage.self, from: encoded)

        XCTAssertEqual(decoded.id, "msg-1")
        XCTAssertEqual(decoded.type, "download.add")
        XCTAssertEqual(decoded.browser, "chrome")
        XCTAssertEqual(decoded.payload?.url, "https://example.com/file.dmg")
        XCTAssertEqual(decoded.payload?.cookies?.first?.name, "session")
        XCTAssertEqual(decoded.payload?.cookies?.first?.httpOnly, true)
    }

    // Bridge Server: 50 concurrent requests over real Unix domain socket
    func testConcurrent50Requests() async throws {
        let delegate = MockBridgeDelegate()
        let server = BridgeServer(
            socketPath: testSocketPath,
            delegate: delegate,
            peerValidator: AllowAllPeerValidator()
        )
        try server.start()
        defer { server.stop() }

        let client = UnixSocketClient(socketPath: testSocketPath)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let msg = BridgeMessage(id: "req-\(i)", type: "hello")
                    guard let data = try? JSONEncoder().encode(msg),
                          let resData = try? await client.sendRequest(data),
                          let res = try? JSONDecoder().decode(BridgeResponse.self, from: resData) else {
                        XCTFail("Request \(i) failed")
                        return
                    }
                    XCTAssertEqual(res.id, "req-\(i)")
                    XCTAssertTrue(res.ok)
                }
            }
        }
    }

    // Bridge Server: Malformed message handling
    func testMalformedMessageHandling() async throws {
        let server = BridgeServer(
            socketPath: testSocketPath,
            delegate: MockBridgeDelegate(),
            peerValidator: AllowAllPeerValidator()
        )
        try server.start()
        defer { server.stop() }

        let client = UnixSocketClient(socketPath: testSocketPath)
        let garbageData = "THIS IS NOT JSON {{{".data(using: .utf8)!

        let resData = try await client.sendRequest(garbageData)
        let response = try JSONDecoder().decode(BridgeResponse.self, from: resData)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.reason, "Malformed JSON message")
    }

    // Bridge Server: Large message rejection (> 1MB)
    func testLargeMessageRejection() async throws {
        let server = BridgeServer(
            socketPath: testSocketPath,
            delegate: MockBridgeDelegate(),
            peerValidator: AllowAllPeerValidator()
        )
        try server.start()
        defer { server.stop() }

        // Craft a header claiming 2 MB length
        var length = UInt32(2 * 1024 * 1024).littleEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(Data(count: 16)) // Send a few bytes

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { XCTFail("Socket creation failed"); return }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        testSocketPath.withCString { cstr in
            withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
                ptr.baseAddress?.copyMemory(from: cstr, byteCount: strlen(cstr) + 1)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, addrLen)
            }
        }
        XCTAssertEqual(connectRes, 0)

        // Write oversized header
        _ = framed.withUnsafeBytes { write(fd, $0.baseAddress, framed.count) }

        // Read response: server must send error response
        var respHeader = Data(count: 4)
        _ = respHeader.withUnsafeMutableBytes { read(fd, $0.baseAddress, 4) }
        if let len = MessageFraming.decodeHeader(from: respHeader) {
            var body = Data(count: Int(len))
            _ = body.withUnsafeMutableBytes { read(fd, $0.baseAddress, Int(len)) }
            let res = try? JSONDecoder().decode(BridgeResponse.self, from: body)
            XCTAssertEqual(res?.ok, false)
            XCTAssertEqual(res?.reason, "Invalid payload length")
        }
    }

    // Bridge Server: Delayed delegate response (slow processing)
    func testDelayedDelegateResponse() async throws {
        let delegate = MockBridgeDelegate()
        delegate.delayNanoseconds = 150_000_000 // 150ms delay

        let server = BridgeServer(
            socketPath: testSocketPath,
            delegate: delegate,
            peerValidator: AllowAllPeerValidator()
        )
        try server.start()
        defer { server.stop() }

        let client = UnixSocketClient(socketPath: testSocketPath)
        let msg = BridgeMessage(id: "delayed-1", type: "hello")
        let data = try JSONEncoder().encode(msg)

        let start = Date()
        let resData = try await client.sendRequest(data)
        let duration = Date().timeIntervalSince(start)

        let response = try JSONDecoder().decode(BridgeResponse.self, from: resData)
        XCTAssertEqual(response.id, "delayed-1")
        XCTAssertTrue(response.ok)
        XCTAssertGreaterThanOrEqual(duration, 0.12)
    }

    // NativeHostInstaller: Manifest generation verification
    func testNativeHostInstallerManifestGeneration() {
        let chromeManifest = NativeHostInstaller.generateManifest(nmhPath: "/test/nmh", isFirefox: false)
        XCTAssertTrue(chromeManifest.contains("dev.kodiz.dm"))
        XCTAssertTrue(chromeManifest.contains("/test/nmh"))
        XCTAssertTrue(chromeManifest.contains("chrome-extension://\(NativeHostInstaller.extensionId)/"))
        XCTAssertTrue(chromeManifest.contains("allowed_origins"))

        let firefoxManifest = NativeHostInstaller.generateManifest(nmhPath: "/test/nmh", isFirefox: true)
        XCTAssertTrue(firefoxManifest.contains("dev.kodiz.dm"))
        XCTAssertTrue(firefoxManifest.contains("kodiz@kodiz.dev"))
        XCTAssertTrue(firefoxManifest.contains("allowed_extensions"))
    }
}

import XCTest
@testable import KodizBridgeProtocol

final class BridgeProtocolTests: XCTestCase {
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
}

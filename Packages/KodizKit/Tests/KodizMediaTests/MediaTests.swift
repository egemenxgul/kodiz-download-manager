import XCTest
import KodizBridgeProtocol
@testable import KodizMedia

final class MediaTests: XCTestCase {
    func testNetscapeCookieFormatting() {
        let cookies = [
            BridgeCookie(name: "SID", value: "secret123", domain: ".youtube.com", path: "/", secure: true, httpOnly: true),
            BridgeCookie(name: "PREF", value: "f1=50000000", domain: ".youtube.com", path: "/", secure: false, httpOnly: false)
        ]

        let exported = NetscapeCookieExporter.format(cookies: cookies)
        XCTAssertTrue(exported.contains("#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t"))
        XCTAssertTrue(exported.contains(".youtube.com\tTRUE\t/\tFALSE\t"))
        XCTAssertTrue(exported.contains("secret123"))
    }

    func testMediaProgressParserJSON() {
        let line = "download:KDM {\"downloaded_bytes\": 15000000, \"total_bytes\": 30000000, \"speed\": 5000000, \"eta\": 3}"
        let parsed = MediaProgressParser.parseLine(line)

        XCTAssertNotNil(parsed.progress)
        XCTAssertEqual(parsed.progress?.downloadedBytes, 15000000)
        XCTAssertEqual(parsed.progress?.totalBytes, 30000000)
        XCTAssertEqual(parsed.progress?.speed, 5000000)
        XCTAssertEqual(parsed.progress?.eta, 3)
        XCTAssertEqual(parsed.progress?.percentage, 50.0)
    }

    func testMediaProgressParserAdvice() {
        let line = "ERROR: [youtube] 12345: Sign in to confirm your age. This video may be inappropriate for some users."
        let parsed = MediaProgressParser.parseLine(line)

        XCTAssertNotNil(parsed.errorAdvice)
        XCTAssertTrue(parsed.errorAdvice!.contains("Giriş yapmanız"))
    }

    func testMediaProgressParserFinalPath() {
        let line = "after_move:KDMFILE /Users/test/Downloads/video.mp4"
        let parsed = MediaProgressParser.parseLine(line)

        XCTAssertEqual(parsed.finalPath, "/Users/test/Downloads/video.mp4")
    }
}

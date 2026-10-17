import Foundation
import Network

final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.readRequest()
            }
        }
        connection.start(queue: .global())
    }

    private func readRequest() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 8192) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, error == nil else { return }
            guard let requestStr = String(data: data, encoding: .utf8) else { return }

            self.handleRequest(requestStr)
        }
    }

    private func handleRequest(_ requestStr: String) {
        let lines = requestStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }

        let path = parts[1]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let kv = line.components(separatedBy: ": ")
            if kv.count == 2 {
                headers[kv[0].lowercased()] = kv[1]
            }
        }

        let rangeHeader = headers["range"]

        switch path {
        case "/rate-limited":
            sendResponse(status: 429, headers: ["Retry-After": "2"], body: Data("Too Many Requests".utf8))

        case "/no-range":
            // Always 200 OK without Accept-Ranges
            let dummy = Data(repeating: 0x41, count: 1024 * 1024 * 2) // 2MB
            sendResponse(status: 200, headers: [
                "Content-Type": "application/octet-stream",
                "Content-Length": "\(dummy.count)"
            ], body: dummy)

        case "/flakey":
            // Drop connection after sending a tiny chunk
            let dummy = Data(repeating: 0x42, count: 32 * 1024)
            sendDataAndClose(status: 200, body: dummy)

        case let p where p.hasPrefix("/normal") || p.hasPrefix("/large"):
            let totalSize: Int64 = p.hasPrefix("/large") ? (1024 * 1024 * 1024 * 2) : (1024 * 1024 * 10) // 2GB or 10MB

            if let range = rangeHeader, range.hasPrefix("bytes=") {
                let rangeSpec = String(range.dropFirst("bytes=".count))
                let rangeParts = rangeSpec.components(separatedBy: "-")

                let start = Int64(rangeParts[0]) ?? 0
                let end: Int64
                if rangeParts.count > 1 && !rangeParts[1].isEmpty {
                    end = min(totalSize - 1, Int64(rangeParts[1]) ?? (totalSize - 1))
                } else {
                    end = totalSize - 1
                }

                let length = max(0, end - start + 1)
                let bodyData = Data(repeating: 0x58, count: Int(min(length, 1024 * 1024)))

                sendResponse(status: 206, headers: [
                    "Content-Range": "bytes \(start)-\(end)/\(totalSize)",
                    "Content-Length": "\(length)",
                    "Content-Type": "application/octet-stream",
                    "Accept-Ranges": "bytes",
                    "ETag": "\"test-etag-12345\""
                ], body: bodyData)
            } else {
                sendResponse(status: 200, headers: [
                    "Content-Length": "\(totalSize)",
                    "Content-Type": "application/octet-stream",
                    "Accept-Ranges": "bytes",
                    "ETag": "\"test-etag-12345\""
                ], body: Data(repeating: 0x58, count: 64 * 1024))
            }

        default:
            sendResponse(status: 404, headers: [:], body: Data("Not Found".utf8))
        }
    }

    private func sendResponse(status: Int, headers: [String: String], body: Data) {
        var statusText = "OK"
        if status == 206 { statusText = "Partial Content" }
        if status == 429 { statusText = "Too Many Requests" }
        if status == 404 { statusText = "Not Found" }

        var headerStr = "HTTP/1.1 \(status) \(statusText)\r\n"
        for (k, v) in headers {
            headerStr += "\(k): \(v)\r\n"
        }
        headerStr += "Connection: close\r\n\r\n"

        var responseData = Data(headerStr.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
    }

    private func sendDataAndClose(status: Int, body: Data) {
        let headerStr = "HTTP/1.1 \(status) OK\r\nContent-Length: 10485760\r\nConnection: close\r\n\r\n"
        var data = Data(headerStr.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
    }
}

@main
struct TestServerMain {
    static func main() {
        let port: UInt16 = 8089
        guard let listener = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!) else {
            print("Failed to bind TestServer on port \(port)")
            exit(1)
        }

        print("TestServer running on http://127.0.0.1:\(port)")
        print("Endpoints:")
        print("  /normal         - Standard Range supported file")
        print("  /no-range       - Server ignores Range (200 OK)")
        print("  /rate-limited   - 429 Too Many Requests with Retry-After")
        print("  /flakey         - Connection abruptly drops")
        print("  /large          - 2GB virtual sparse stream")

        listener.newConnectionHandler = { newConn in
            let httpConn = HTTPConnection(connection: newConn)
            httpConn.start()
        }

        listener.start(queue: .global())
        dispatchMain()
    }
}

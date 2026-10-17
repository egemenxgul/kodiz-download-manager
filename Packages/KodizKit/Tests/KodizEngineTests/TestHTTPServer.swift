import Foundation
import Network
import CryptoKit
import zlib

// MARK: - Deterministic Data Generator & SHA-256

public struct DeterministicData: Sendable {
    public static let defaultSeed: UInt64 = 0x123456789ABCDEF0
    public static let changedSeed: UInt64 = 0x9876543210FEDCBA

    public static func byte(at offset: Int64, seed: UInt64 = defaultSeed) -> UInt8 {
        var x = UInt64(bitPattern: offset) &+ seed
        x = (x ^ (x >> 30)) &* 0xbf58476d1ce4e5b9
        x = (x ^ (x >> 27)) &* 0x94d049bb133111eb
        x = x ^ (x >> 31)
        return UInt8(truncatingIfNeeded: x)
    }

    public static func generateChunk(offset: Int64, count: Int, seed: UInt64 = defaultSeed) -> Data {
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            guard let ptr = buffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<count {
                ptr[i] = byte(at: offset + Int64(i), seed: seed)
            }
        }
        return data
    }

    public static func sha256(totalBytes: Int64, seed: UInt64 = defaultSeed) -> String {
        var hasher = SHA256()
        let chunkSize = 64 * 1024
        var offset: Int64 = 0
        while offset < totalBytes {
            let count = Int(min(Int64(chunkSize), totalBytes - offset))
            let chunk = generateChunk(offset: offset, count: count, seed: seed)
            hasher.update(data: chunk)
            offset += Int64(count)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func fileSHA256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 64 * 1024)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Gzip Helper

public struct GzipHelper: Sendable {
    public static func compress(_ data: Data) -> Data? {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { deflateEnd(&stream) }

        var compressed = Data(count: max(16384, data.count + 64))
        let capacity = compressed.count
        var output = Data()

        return data.withUnsafeBytes { inputBuf -> Data? in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBuf.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)

            var status = Z_OK
            while status == Z_OK {
                compressed.withUnsafeMutableBytes { outBuf in
                    stream.next_out = outBuf.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(capacity)
                    status = deflate(&stream, Z_FINISH)
                    let written = capacity - Int(stream.avail_out)
                    if written > 0 {
                        output.append(outBuf.bindMemory(to: UInt8.self).baseAddress!, count: written)
                    }
                }
            }
            return status == Z_STREAM_END ? output : nil
        }
    }
}

// MARK: - Server State

public actor TestServerStats {
    public var acceptedConnections: Int = 0
    public var activeConnections: Int = 0
    public var totalBytesServed: Int64 = 0
    public var requestsCount: [String: Int] = [:]
    public var flakyAttemptMap: [String: Int] = [:]
    public var etagChanged: Bool = false

    public func incrementAccepted() {
        acceptedConnections += 1
        activeConnections += 1
    }

    public func decrementActive() {
        if activeConnections > 0 {
            activeConnections -= 1
        }
    }

    public func addBytesServed(_ bytes: Int64) {
        totalBytesServed += bytes
    }

    public func recordRequest(path: String) -> Int {
        let count = (requestsCount[path] ?? 0) + 1
        requestsCount[path] = count
        return count
    }

    public func getFlakyAttempt(for key: String) -> Int {
        let count = (flakyAttemptMap[key] ?? 0) + 1
        flakyAttemptMap[key] = count
        return count
    }

    public func setEtagChanged(_ val: Bool) {
        etagChanged = val
    }

    public func reset() {
        acceptedConnections = 0
        activeConnections = 0
        totalBytesServed = 0
        requestsCount.removeAll()
        flakyAttemptMap.removeAll()
        etagChanged = false
    }
}

// MARK: - HTTP Request

public struct HTTPParsedRequest: Sendable {
    public let method: String
    public let path: String
    public let queryItems: [URLQueryItem]
    public let headers: [String: String]
    public let rawQuery: String?

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    public func queryParam(_ name: String) -> String? {
        queryItems.first(where: { $0.name == name })?.value
    }
}

// MARK: - TestHTTPServer

public final class TestHTTPServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.kodiz.testserver", qos: .userInitiated, attributes: .concurrent)
    public let stats = TestServerStats()
    public private(set) var port: UInt16 = 0

    public init() {}

    public func start(preferredPort: UInt16 = 0) async throws -> UInt16 {
        let nwPort: NWEndpoint.Port = preferredPort == 0 ? .any : NWEndpoint.Port(rawValue: preferredPort)!
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener

        final class ResumeBox: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func claim() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if !done {
                    done = true
                    return true
                }
                return false
            }
        }

        let box = ResumeBox()

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let actualPort = listener.port?.rawValue {
                        self.port = actualPort
                        if box.claim() {
                            continuation.resume(returning: actualPort)
                        }
                    }
                case .failed(let error):
                    if box.claim() {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                self.handleNewConnection(connection)
            }

            listener.start(queue: self.queue)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleNewConnection(_ connection: NWConnection) {
        Task {
            await stats.incrementAccepted()
        }

        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { [weak self] in
                    await self?.stats.decrementActive()
                }
            } else if case .cancelled = state {
                Task { [weak self] in
                    await self?.stats.decrementActive()
                }
            }
        }

        connection.start(queue: queue)
        readNextRequest(connection: connection)
    }

    private func readNextRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 16384) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            guard let data = content, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }

            guard let requestStr = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            guard let req = self.parseRequest(requestStr) else {
                self.sendRawResponse(connection: connection, status: 400, statusText: "Bad Request", headers: [:], body: Data("Bad Request".utf8), closeConnection: true)
                return
            }

            Task {
                await self.dispatchRequest(connection: connection, request: req)
            }
        }
    }

    private func parseRequest(_ str: String) -> HTTPParsedRequest? {
        let lines = str.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        let fullPath = parts[1]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
                let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        let comps = URLComponents(string: "http://localhost" + fullPath)
        let path = comps?.path ?? fullPath
        let queryItems = comps?.queryItems ?? []

        return HTTPParsedRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            headers: headers,
            rawQuery: comps?.query
        )
    }

    private func dispatchRequest(connection: NWConnection, request: HTTPParsedRequest) async {
        let reqCount = await stats.recordRequest(path: request.path)
        let activeConns = await stats.activeConnections

        // Default size is 10 MB if not specified
        let defaultSize: Int64 = 10 * 1024 * 1024
        let sizeParam = request.queryParam("size").flatMap { Int64($0) } ?? defaultSize

        switch request.path {
        case "/range":
            await handleRange(connection: connection, request: request, totalSize: sizeParam)

        case "/norange":
            await handleNoRange(connection: connection, request: request, totalSize: sizeParam)

        case "/unknown-length":
            await handleUnknownLength(connection: connection, request: request, totalSize: sizeParam)

        case "/ratelimit":
            let limitThreshold = request.queryParam("limit").flatMap { Int($0) } ?? 3
            let maxConns = request.queryParam("max_conns").flatMap { Int($0) } ?? 4

            if reqCount <= limitThreshold {
                sendRawResponse(
                    connection: connection,
                    status: 429,
                    statusText: "Too Many Requests",
                    headers: ["Retry-After": "1", "Content-Type": "text/plain"],
                    body: Data("Rate limited\n".utf8),
                    closeConnection: false
                )
            } else if activeConns > maxConns {
                sendRawResponse(
                    connection: connection,
                    status: 503,
                    statusText: "Service Unavailable",
                    headers: ["Retry-After": "1", "Content-Type": "text/plain"],
                    body: Data("Too many concurrent connections\n".utf8),
                    closeConnection: false
                )
            } else {
                await handleRange(connection: connection, request: request, totalSize: sizeParam)
            }

        case "/flaky":
            await handleFlaky(connection: connection, request: request, totalSize: sizeParam)

        case "/slow":
            let speed = request.queryParam("speed").flatMap { Int($0) } ?? (50 * 1024)
            await handleSlow(connection: connection, request: request, totalSize: sizeParam, bytesPerSec: speed)

        case "/etag-change":
            await handleETagChange(connection: connection, request: request, totalSize: sizeParam, reqCount: reqCount)

        case "/redirect":
            sendRawResponse(
                connection: connection,
                status: 302,
                statusText: "Found",
                headers: ["Location": "/redirect-2" + (request.rawQuery.map { "?\($0)" } ?? "")],
                body: Data(),
                closeConnection: false
            )

        case "/redirect-2":
            sendRawResponse(
                connection: connection,
                status: 302,
                statusText: "Found",
                headers: ["Location": "/range" + (request.rawQuery.map { "?\($0)" } ?? "")],
                body: Data(),
                closeConnection: false
            )

        case "/gzip-force":
            await handleGzipForce(connection: connection, request: request, totalSize: sizeParam)

        case "/disposition":
            await handleDisposition(connection: connection, request: request, totalSize: sizeParam)

        case "/reset":
            await stats.reset()
            sendRawResponse(connection: connection, status: 200, statusText: "OK", headers: [:], body: Data("OK".utf8), closeConnection: false)

        default:
            sendRawResponse(
                connection: connection,
                status: 404,
                statusText: "Not Found",
                headers: ["Content-Type": "text/plain"],
                body: Data("Not Found".utf8),
                closeConnection: false
            )
        }
    }

    // MARK: - Handlers

    private func handleRange(
        connection: NWConnection,
        request: HTTPParsedRequest,
        totalSize: Int64,
        seed: UInt64 = DeterministicData.defaultSeed,
        etag: String = "\"kdm-test-etag\"",
        extraHeaders: [String: String] = [:]
    ) async {
        if let rangeHdr = request.header("range"), rangeHdr.hasPrefix("bytes=") {
            let spec = String(rangeHdr.dropFirst("bytes=".count))
            let parts = spec.components(separatedBy: "-")
            let start = Int64(parts[0]) ?? 0
            let end: Int64
            if parts.count > 1 && !parts[1].isEmpty {
                end = min(totalSize - 1, Int64(parts[1]) ?? (totalSize - 1))
            } else {
                end = totalSize - 1
            }

            guard start <= end && start < totalSize else {
                sendRawResponse(
                    connection: connection,
                    status: 416,
                    statusText: "Range Not Satisfiable",
                    headers: ["Content-Range": "bytes */\(totalSize)"],
                    body: Data(),
                    closeConnection: false
                )
                return
            }

            let length = Int(end - start + 1)
            var headers: [String: String] = [
                "Content-Type": "application/octet-stream",
                "Content-Range": "bytes \(start)-\(end)/\(totalSize)",
                "Content-Length": "\(length)",
                "Accept-Ranges": "bytes",
                "ETag": etag
            ]
            for (k, v) in extraHeaders { headers[k] = v }

            await sendStreamedResponse(
                connection: connection,
                status: 206,
                statusText: "Partial Content",
                headers: headers,
                offset: start,
                totalBytesToSend: length,
                seed: seed
            )
        } else {
            // Full content
            var headers: [String: String] = [
                "Content-Type": "application/octet-stream",
                "Content-Length": "\(totalSize)",
                "Accept-Ranges": "bytes",
                "ETag": etag
            ]
            for (k, v) in extraHeaders { headers[k] = v }

            await sendStreamedResponse(
                connection: connection,
                status: 200,
                statusText: "OK",
                headers: headers,
                offset: 0,
                totalBytesToSend: Int(totalSize),
                seed: seed
            )
        }
    }

    private func handleNoRange(connection: NWConnection, request: HTTPParsedRequest, totalSize: Int64) async {
        // Ignores Range header completely, returns 200 OK without Accept-Ranges
        let headers: [String: String] = [
            "Content-Type": "application/octet-stream",
            "Content-Length": "\(totalSize)",
            "Accept-Ranges": "none"
        ]

        await sendStreamedResponse(
            connection: connection,
            status: 200,
            statusText: "OK",
            headers: headers,
            offset: 0,
            totalBytesToSend: Int(totalSize),
            seed: DeterministicData.defaultSeed
        )
    }

    private func handleUnknownLength(connection: NWConnection, request: HTTPParsedRequest, totalSize: Int64) async {
        // No Content-Length, closes connection at end
        let headers: [String: String] = [
            "Content-Type": "application/octet-stream",
            "Connection": "close"
        ]

        await sendStreamedResponse(
            connection: connection,
            status: 200,
            statusText: "OK",
            headers: headers,
            offset: 0,
            totalBytesToSend: Int(totalSize),
            seed: DeterministicData.defaultSeed,
            closeAtEnd: true
        )
    }

    private func handleFlaky(connection: NWConnection, request: HTTPParsedRequest, totalSize: Int64) async {
        let rangeHdr = request.header("range") ?? "all"
        let attempt = await stats.getFlakyAttempt(for: rangeHdr)

        // If attempt is odd (1, 3, ...), drop the connection midway
        // If attempt is even (2, 4, ...), allow it to succeed!
        if attempt % 2 == 1 {
            var headerStr = "HTTP/1.1 206 Partial Content\r\n"
            headerStr += "Content-Type: application/octet-stream\r\n"
            headerStr += "Content-Range: bytes 0-\(totalSize - 1)/\(totalSize)\r\n"
            headerStr += "Content-Length: \(totalSize)\r\n"
            headerStr += "Accept-Ranges: bytes\r\n\r\n"

            let partialChunk = DeterministicData.generateChunk(offset: 0, count: min(64 * 1024, Int(totalSize)))
            var packet = Data(headerStr.utf8)
            packet.append(partialChunk)

            connection.send(content: packet, completion: .contentProcessed { _ in
                // Force abrupt connection drop
                connection.cancel()
            })
            await stats.addBytesServed(Int64(partialChunk.count))
        } else {
            // Success on retry
            await handleRange(connection: connection, request: request, totalSize: totalSize)
        }
    }

    private func handleSlow(connection: NWConnection, request: HTTPParsedRequest, totalSize: Int64, bytesPerSec: Int) async {
        let start: Int64
        let end: Int64
        let status: Int
        let statusText: String
        var headers: [String: String] = [
            "Content-Type": "application/octet-stream",
            "Accept-Ranges": "bytes",
            "ETag": "\"kdm-slow-etag\""
        ]

        if let rangeHdr = request.header("range"), rangeHdr.hasPrefix("bytes=") {
            let spec = String(rangeHdr.dropFirst("bytes=".count))
            let parts = spec.components(separatedBy: "-")
            start = Int64(parts[0]) ?? 0
            end = parts.count > 1 && !parts[1].isEmpty ? (Int64(parts[1]) ?? (totalSize - 1)) : (totalSize - 1)
            status = 206
            statusText = "Partial Content"
            let len = end - start + 1
            headers["Content-Range"] = "bytes \(start)-\(end)/\(totalSize)"
            headers["Content-Length"] = "\(len)"
        } else {
            start = 0
            end = totalSize - 1
            status = 200
            statusText = "OK"
            headers["Content-Length"] = "\(totalSize)"
        }

        let totalToSend = Int(end - start + 1)
        var headerStr = "HTTP/1.1 \(status) \(statusText)\r\n"
        for (k, v) in headers {
            headerStr += "\(k): \(v)\r\n"
        }
        headerStr += "Connection: keep-alive\r\n\r\n"

        connection.send(content: Data(headerStr.utf8), completion: .contentProcessed { _ in })

        // Send at throttled speed
        let subchunkSize = min(4096, max(512, bytesPerSec / 10))
        let intervalSec = Double(subchunkSize) / Double(bytesPerSec)
        var sent = 0

        while sent < totalToSend {
            let chunkCount = min(subchunkSize, totalToSend - sent)
            let chunk = DeterministicData.generateChunk(offset: start + Int64(sent), count: chunkCount)
            await stats.addBytesServed(Int64(chunkCount))

            let sleepNs = UInt64(intervalSec * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepNs)

            connection.send(content: chunk, completion: .contentProcessed { _ in })
            sent += chunkCount
        }

        readNextRequest(connection: connection)
    }

    private func handleETagChange(
        connection: NWConnection,
        request: HTTPParsedRequest,
        totalSize: Int64,
        reqCount: Int
    ) async {
        // ETag changes to v2 after the 2nd request or when etagChanged is true
        let explicitChanged = await stats.etagChanged
        let hasChanged = explicitChanged || reqCount > 2

        if !hasChanged {
            await handleRange(
                connection: connection,
                request: request,
                totalSize: totalSize,
                seed: DeterministicData.defaultSeed,
                etag: "\"etag-v1\""
            )
            return
        }

        // Now ETag is "etag-v2"
        let currentETag = "\"etag-v2\""
        let ifRange = request.header("if-range")

        if let ifRange = ifRange, ifRange != currentETag {
            // RFC 7233 §3.2: When If-Range fails, return 200 OK with full representation!
            let headers: [String: String] = [
                "Content-Type": "application/octet-stream",
                "Content-Length": "\(totalSize)",
                "Accept-Ranges": "bytes",
                "ETag": currentETag
            ]

            await sendStreamedResponse(
                connection: connection,
                status: 200,
                statusText: "OK",
                headers: headers,
                offset: 0,
                totalBytesToSend: Int(totalSize),
                seed: DeterministicData.changedSeed
            )
        } else {
            await handleRange(
                connection: connection,
                request: request,
                totalSize: totalSize,
                seed: DeterministicData.changedSeed,
                etag: currentETag
            )
        }
    }

    private func handleGzipForce(connection: NWConnection, request: HTTPParsedRequest, totalSize: Int64) async {
        let acceptEncoding = request.header("accept-encoding") ?? ""
        let isIdentity = acceptEncoding.contains("identity")

        if isIdentity {
            // Identity explicitly requested: return uncompressed
            await handleRange(connection: connection, request: request, totalSize: totalSize)
        } else {
            // Force gzip!
            let rawData = DeterministicData.generateChunk(offset: 0, count: Int(min(totalSize, 1024 * 1024)))
            let gzipped = GzipHelper.compress(rawData) ?? rawData

            let headers: [String: String] = [
                "Content-Type": "application/octet-stream",
                "Content-Encoding": "gzip",
                "Content-Length": "\(gzipped.count)"
            ]

            sendRawResponse(
                connection: connection,
                status: 200,
                statusText: "OK",
                headers: headers,
                body: gzipped,
                closeConnection: false
            )
        }
    }

    private func handleDisposition(connection: NWConnection, request: HTTPParsedRequest, totalSize: Int64) async {
        let extra = [
            "Content-Disposition": "attachment; filename*=UTF-8''T%C3%BCrk%C3%A7e%20dosya.zip"
        ]
        await handleRange(connection: connection, request: request, totalSize: totalSize, extraHeaders: extra)
    }

    // MARK: - Streaming & Sending

    private func sendStreamedResponse(
        connection: NWConnection,
        status: Int,
        statusText: String,
        headers: [String: String],
        offset: Int64,
        totalBytesToSend: Int,
        seed: UInt64,
        closeAtEnd: Bool = false
    ) async {
        var headerStr = "HTTP/1.1 \(status) \(statusText)\r\n"
        for (k, v) in headers {
            headerStr += "\(k): \(v)\r\n"
        }
        if closeAtEnd {
            headerStr += "Connection: close\r\n\r\n"
        } else {
            headerStr += "Connection: keep-alive\r\n\r\n"
        }

        let headerSuccess: Bool = await withCheckedContinuation { cont in
            connection.send(content: Data(headerStr.utf8), completion: .contentProcessed { err in
                cont.resume(returning: err == nil)
            })
        }
        guard headerSuccess else { return }

        let chunkSize = 64 * 1024
        var sent = 0

        while sent < totalBytesToSend {
            let count = min(chunkSize, totalBytesToSend - sent)
            let chunk = DeterministicData.generateChunk(offset: offset + Int64(sent), count: count, seed: seed)

            let isLast = (sent + count >= totalBytesToSend)
            let sendSuccess: Bool = await withCheckedContinuation { cont in
                connection.send(content: chunk, completion: .contentProcessed { err in
                    if isLast && closeAtEnd {
                        connection.cancel()
                    }
                    cont.resume(returning: err == nil)
                })
            }

            if !sendSuccess {
                break
            }

            await stats.addBytesServed(Int64(count))
            sent += count
        }

        if !closeAtEnd {
            readNextRequest(connection: connection)
        }
    }

    private func sendRawResponse(
        connection: NWConnection,
        status: Int,
        statusText: String,
        headers: [String: String],
        body: Data,
        closeConnection: Bool
    ) {
        var headerStr = "HTTP/1.1 \(status) \(statusText)\r\n"
        for (k, v) in headers {
            headerStr += "\(k): \(v)\r\n"
        }
        if headers["Content-Length"] == nil {
            headerStr += "Content-Length: \(body.count)\r\n"
        }
        if closeConnection {
            headerStr += "Connection: close\r\n\r\n"
        } else {
            headerStr += "Connection: keep-alive\r\n\r\n"
        }

        var packet = Data(headerStr.utf8)
        packet.append(body)

        connection.send(content: packet, completion: .contentProcessed { [weak self] _ in
            if closeConnection {
                connection.cancel()
            } else {
                self?.readNextRequest(connection: connection)
            }
        })
    }
}

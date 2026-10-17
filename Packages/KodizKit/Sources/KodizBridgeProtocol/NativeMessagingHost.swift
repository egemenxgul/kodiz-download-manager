import Foundation

public final class NativeMessagingHost: @unchecked Sendable {
    private let socketPath: String
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle

    public init(socketPath: String? = nil) {
        if let socketPath = socketPath {
            self.socketPath = socketPath
        } else {
            // App Group container socket path
            let fileManager = FileManager.default
            let home = fileManager.homeDirectoryForCurrentUser
            let defaultSocket = home.appendingPathComponent("Library/Application Support/Kodiz Download Manager/bridge.sock").path
            self.socketPath = defaultSocket
        }
        self.stdinHandle = FileHandle.standardInput
        self.stdoutHandle = FileHandle.standardOutput
    }

    public func run() async {
        while true {
            guard let messageData = readMessage() else {
                break
            }

            do {
                let decoder = JSONDecoder()
                let message = try decoder.decode(BridgeMessage.self, from: messageData)
                let response = await handleMessage(message)
                let encoder = JSONEncoder()
                let responseData = try encoder.encode(response)
                writeMessage(responseData)
            } catch {
                let errResponse = BridgeResponse(id: "error", ok: false, reason: error.localizedDescription)
                if let responseData = try? JSONEncoder().encode(errResponse) {
                    writeMessage(responseData)
                }
            }
        }
    }

    private func readMessage() -> Data? {
        let lengthData = stdinHandle.readData(ofLength: 4)
        guard lengthData.count == 4 else { return nil }

        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        guard length > 0 && length <= 1024 * 1024 else { return nil } // 1MB max

        var received = Data()
        while received.count < Int(length) {
            let chunk = stdinHandle.readData(ofLength: Int(length) - received.count)
            if chunk.isEmpty { return nil }
            received.append(chunk)
        }
        return received
    }

    private func writeMessage(_ data: Data) {
        let framed = MessageFraming.encode(data)
        stdoutHandle.write(framed)
    }

    private func handleMessage(_ message: BridgeMessage) async -> BridgeResponse {
        // Handle hello locally or forward via unix socket
        if message.type == "hello" {
            return BridgeResponse(id: message.id, ok: true)
        }

        // Forward to socket if available
        let client = UnixSocketClient(socketPath: socketPath)
        do {
            let encoder = JSONEncoder()
            let reqData = try encoder.encode(message)
            let resData = try await client.sendRequest(reqData)
            let response = try JSONDecoder().decode(BridgeResponse.self, from: resData)
            return response
        } catch {
            return BridgeResponse(id: message.id, ok: false, reason: "Socket error: \(error.localizedDescription)")
        }
    }
}

public actor UnixSocketClient {
    private let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func sendRequest(_ data: Data) async throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard socketPath.utf8.count < maxLen else {
            throw POSIXError(.ENAMETOOLONG)
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                ptr.baseAddress?.copyMemory(from: cstr, byteCount: strlen(cstr) + 1)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, addrLen)
            }
        }

        guard connectRes == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECONNREFUSED)
        }

        let framed = MessageFraming.encode(data)
        let written = framed.withUnsafeBytes { ptr in
            write(fd, ptr.baseAddress, framed.count)
        }
        guard written == framed.count else {
            throw POSIXError(.EIO)
        }

        var header = Data(count: 4)
        var totalRead = 0
        while totalRead < 4 {
            let n = header.withUnsafeMutableBytes { ptr in
                read(fd, ptr.baseAddress! + totalRead, 4 - totalRead)
            }
            if n <= 0 { throw POSIXError(.ECONNRESET) }
            totalRead += n
        }

        guard let payloadLen = MessageFraming.decodeHeader(from: header), payloadLen <= 1024 * 1024 else {
            throw POSIXError(.EBADMSG)
        }

        var responsePayload = Data(count: Int(payloadLen))
        var payloadRead = 0
        while payloadRead < Int(payloadLen) {
            let n = responsePayload.withUnsafeMutableBytes { ptr in
                read(fd, ptr.baseAddress! + payloadRead, Int(payloadLen) - payloadRead)
            }
            if n <= 0 { throw POSIXError(.ECONNRESET) }
            payloadRead += n
        }

        return responsePayload
    }
}

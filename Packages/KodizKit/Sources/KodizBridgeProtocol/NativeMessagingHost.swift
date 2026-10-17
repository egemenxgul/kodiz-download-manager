import Foundation
import AppKit

public final class NativeMessagingHost: @unchecked Sendable {
    private let socketPath: String

    public init(socketPath: String? = nil) {
        if let socketPath = socketPath {
            self.socketPath = socketPath
        } else {
            self.socketPath = (try? BridgeSocketPath.resolveSocketPath()) ?? ""
        }
    }

    public func run() async {
        while true {
            guard let messageData = readMessageFromStdin() else {
                break
            }

            do {
                let decoder = JSONDecoder()
                let message = try decoder.decode(BridgeMessage.self, from: messageData)
                let response = await handleMessage(message)
                let encoder = JSONEncoder()
                let responseData = try encoder.encode(response)
                writeMessageToStdout(responseData)
            } catch {
                let errResponse = BridgeResponse(id: "error", ok: false, reason: error.localizedDescription)
                if let responseData = try? JSONEncoder().encode(errResponse) {
                    writeMessageToStdout(responseData)
                }
            }
        }
    }

    private func readMessageFromStdin() -> Data? {
        var lengthBytes = [UInt8](repeating: 0, count: 4)
        var totalRead = 0
        while totalRead < 4 {
            let n = lengthBytes.withUnsafeMutableBytes { ptr in
                read(STDIN_FILENO, ptr.baseAddress! + totalRead, 4 - totalRead)
            }
            if n <= 0 { return nil }
            totalRead += n
        }

        let length = UInt32(lengthBytes[0]) |
                     (UInt32(lengthBytes[1]) << 8) |
                     (UInt32(lengthBytes[2]) << 16) |
                     (UInt32(lengthBytes[3]) << 24)

        guard length > 0 && length <= 1024 * 1024 else { return nil }

        var payload = Data(count: Int(length))
        var payloadRead = 0
        while payloadRead < Int(length) {
            let n = payload.withUnsafeMutableBytes { ptr in
                read(STDIN_FILENO, ptr.baseAddress! + payloadRead, Int(length) - payloadRead)
            }
            if n <= 0 { return nil }
            payloadRead += n
        }
        return payload
    }

    private func writeMessageToStdout(_ data: Data) {
        let framed = MessageFraming.encode(data)
        framed.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var written = 0
            let total = ptr.count
            while written < total {
                let n = write(STDOUT_FILENO, base + written, total - written)
                if n <= 0 { break }
                written += n
            }
        }
    }

    private func handleMessage(_ message: BridgeMessage) async -> BridgeResponse {
        // Handle hello locally without launching app
        if message.type == "hello" {
            return BridgeResponse(id: message.id, ok: true)
        }

        let client = UnixSocketClient(socketPath: socketPath)
        let encoder = JSONEncoder()
        guard let reqData = try? encoder.encode(message) else {
            return BridgeResponse(id: message.id, ok: false, reason: "Failed to encode message")
        }

        // Try sending to running socket first
        do {
            let resData = try await client.sendRequest(reqData)
            return try JSONDecoder().decode(BridgeResponse.self, from: resData)
        } catch {
            // If connection refused / socket missing, and message requires app (e.g. download.add, media.download)
            if message.type == "download.add" || message.type == "media.download" {
                launchAppInBackground()

                // Poll socket for up to 8 seconds
                let start = Date()
                while Date().timeIntervalSince(start) < 8.0 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    do {
                        let resData = try await client.sendRequest(reqData)
                        return try JSONDecoder().decode(BridgeResponse.self, from: resData)
                    } catch {
                        continue
                    }
                }
            }

            return BridgeResponse(id: message.id, ok: false, reason: "Socket error: \(error.localizedDescription)")
        }
    }

    private func launchAppInBackground() {
        // NMH binary is at: <App>/Contents/Helpers/kodiz-nmh
        let execURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let appURL = execURL
            .deletingLastPathComponent() // Helpers
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // Kodiz Download Manager.app

        guard appURL.pathExtension == "app" || FileManager.default.fileExists(atPath: appURL.path) else {
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.arguments = ["--background"]

        NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
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

        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

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

        // Full write
        let framed = MessageFraming.encode(data)
        let writeSuccess = framed.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            var written = 0
            while written < framed.count {
                let n = write(fd, base + written, framed.count - written)
                if n <= 0 { return false }
                written += n
            }
            return true
        }

        guard writeSuccess else {
            throw POSIXError(.EIO)
        }

        // Full read header
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

        // Full read payload
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

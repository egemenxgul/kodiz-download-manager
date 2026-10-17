import Foundation
import Security

public protocol BridgeServerDelegate: AnyObject, Sendable {
    func handleBridgeMessage(_ message: BridgeMessage) async -> BridgeResponse
}

public protocol BridgePeerValidator: Sendable {
    func validate(clientFd: Int32) -> Bool
}

public struct MacPeerValidator: BridgePeerValidator {
    public init() {}

    public func validate(clientFd: Int32) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KODIZ_ALLOW_UNSIGNED_BRIDGE"] == "1" {
            return true
        }
        #endif

        var token = audit_token_t()
        var tokenSize = socklen_t(MemoryLayout<audit_token_t>.size)

        // SOL_LOCAL is 0 in Darwin
        let ret = getsockopt(clientFd, 0, LOCAL_PEERTOKEN, &token, &tokenSize)
        guard ret == 0 else { return false }

        let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        let guestAttrs: [CFString: Any] = [
            kSecGuestAttributeAudit: tokenData as CFData
        ]

        var secCode: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, guestAttrs as CFDictionary, [], &secCode)
        guard status == errSecSuccess, let code = secCode else {
            return false
        }

        // Must match our Team ID or approved bundle identifiers
        let reqString = "identifier \"dev.kodiz.NativeHost\" or identifier \"dev.kodiz.DownloadManager.SafariExtension\" or identifier \"dev.kodiz.DownloadManager\""
        var secReq: SecRequirement?
        guard SecRequirementCreateWithString(reqString as CFString, [], &secReq) == errSecSuccess,
              let req = secReq else {
            return false
        }

        let checkStatus = SecCodeCheckValidity(code, [], req)
        return checkStatus == errSecSuccess
    }
}

public struct AllowAllPeerValidator: BridgePeerValidator {
    public init() {}
    public func validate(clientFd: Int32) -> Bool { true }
}

public final class BridgeServer: @unchecked Sendable {
    private let socketPath: String
    private weak var delegate: BridgeServerDelegate?
    private let peerValidator: BridgePeerValidator
    private var serverFd: Int32 = -1
    private var isRunning: Bool = false
    private let queue = DispatchQueue(label: "dev.kodiz.BridgeServer", qos: .userInitiated)

    public init(
        socketPath: String? = nil,
        delegate: BridgeServerDelegate? = nil,
        peerValidator: BridgePeerValidator? = nil
    ) {
        self.socketPath = socketPath ?? ((try? BridgeSocketPath.resolveSocketPath()) ?? "")
        self.delegate = delegate
        self.peerValidator = peerValidator ?? MacPeerValidator()
    }

    public func start() throws {
        guard !socketPath.isEmpty else {
            throw POSIXError(.EINVAL)
        }

        // Ensure parent directory exists with 0700 permissions
        let parentDir = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])

        // Unlink old socket file if exists
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        self.serverFd = fd

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
        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, addrLen)
            }
        }

        guard bindRes == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE)
        }

        chmod(socketPath, 0o600)

        guard listen(fd, 64) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        self.isRunning = true
        acceptLoop()
    }

    public func stop() {
        isRunning = false
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }
        unlink(socketPath)
    }

    private func acceptLoop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            while self.isRunning {
                var clientAddr = sockaddr_un()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

                let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        accept(self.serverFd, sa, &clientAddrLen)
                    }
                }

                guard clientFd >= 0 else {
                    if !self.isRunning { break }
                    continue
                }

                // Handle client in an async Task so clientFd lifecycle is completely contained
                Task {
                    await self.handleClientAsync(fd: clientFd)
                }
            }
        }
    }

    private func handleClientAsync(fd: Int32) async {
        // K1 & K6 fix: file descriptor is kept open for the ENTIRE duration of client handling
        // and closed ONLY when the connection terminates.
        defer {
            close(fd)
        }

        // SO_NOSIGPIPE prevents SIGPIPE when peer disconnects unexpectedly
        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        // Read and write timeouts (10 seconds)
        var tv = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // K3: Peer Process Validation
        guard peerValidator.validate(clientFd: fd) else {
            let errorRes = BridgeResponse(id: "unauthorized", ok: false, reason: "Unauthorized peer process")
            if let errData = try? JSONEncoder().encode(errorRes) {
                _ = writeFull(fd: fd, data: MessageFraming.encode(errData))
            }
            return
        }

        // Support persistent connection with multiple request-response cycles
        while isRunning {
            guard let header = readFull(fd: fd, count: 4) else {
                break // Client disconnected or read timed out
            }

            guard let payloadLen = MessageFraming.decodeHeader(from: header),
                  payloadLen > 0, payloadLen <= 1024 * 1024 else {
                let errorRes = BridgeResponse(id: "bad_header", ok: false, reason: "Invalid payload length")
                if let errData = try? JSONEncoder().encode(errorRes) {
                    _ = writeFull(fd: fd, data: MessageFraming.encode(errData))
                }
                break
            }

            guard let payload = readFull(fd: fd, count: Int(payloadLen)) else {
                break
            }

            guard let message = try? JSONDecoder().decode(BridgeMessage.self, from: payload) else {
                let errorRes = BridgeResponse(id: "malformed", ok: false, reason: "Malformed JSON message")
                if let errData = try? JSONEncoder().encode(errorRes) {
                    _ = writeFull(fd: fd, data: MessageFraming.encode(errData))
                }
                break
            }

            // Girdi doğrulaması
            if let errorReason = validateMessageInput(message) {
                let errorRes = BridgeResponse(id: message.id, ok: false, reason: errorReason)
                if let errData = try? JSONEncoder().encode(errorRes) {
                    _ = writeFull(fd: fd, data: MessageFraming.encode(errData))
                }
                continue
            }

            // Await delegate response before writing back!
            let response = await self.delegate?.handleBridgeMessage(message)
                ?? BridgeResponse(id: message.id, ok: true)

            guard let resData = try? JSONEncoder().encode(response) else {
                break
            }

            let framed = MessageFraming.encode(resData)
            if !writeFull(fd: fd, data: framed) {
                break
            }
        }
    }

    private func validateMessageInput(_ message: BridgeMessage) -> String? {
        if message.type == "download.add" || message.type == "media.download" {
            guard let urlString = message.payload?.url, !urlString.isEmpty else {
                return "Missing or empty URL"
            }

            guard urlString.utf8.count <= 4096 else {
                return "URL exceeds 4096 bytes limit"
            }

            guard let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return "Only http and https protocols are supported"
            }

            if let headers = message.payload?.extraHeaders {
                for (k, v) in headers {
                    if k.contains("\r") || k.contains("\n") || v.contains("\r") || v.contains("\n") {
                        return "Header values cannot contain CRLF characters"
                    }
                }
            }
        }
        return nil
    }

    private func readFull(fd: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        var totalRead = 0
        while totalRead < count {
            let n = data.withUnsafeMutableBytes { ptr in
                read(fd, ptr.baseAddress! + totalRead, count - totalRead)
            }
            if n <= 0 { return nil }
            totalRead += n
        }
        return data
    }

    private func writeFull(fd: Int32, data: Data) -> Bool {
        return data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return false }
            var written = 0
            let total = ptr.count
            while written < total {
                let n = write(fd, base + written, total - written)
                if n <= 0 { return false }
                written += n
            }
            return true
        }
    }
}

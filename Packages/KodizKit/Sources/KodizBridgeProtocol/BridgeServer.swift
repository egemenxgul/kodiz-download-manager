import Foundation

public protocol BridgeServerDelegate: AnyObject, Sendable {
    func handleBridgeMessage(_ message: BridgeMessage) async -> BridgeResponse
}

public final class BridgeServer: @unchecked Sendable {
    private let socketPath: String
    private weak var delegate: BridgeServerDelegate?
    private var serverFd: Int32 = -1
    private var isRunning: Bool = false
    private let queue = DispatchQueue(label: "dev.kodiz.BridgeServer", qos: .userInitiated)

    public init(socketPath: String, delegate: BridgeServerDelegate? = nil) {
        self.socketPath = socketPath
        self.delegate = delegate
    }

    public func start() throws {
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

        guard listen(fd, 16) == 0 else {
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

                // Handle client on background queue
                self.queue.async {
                    self.handleClient(fd: clientFd)
                }
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }

        var header = Data(count: 4)
        var totalRead = 0
        while totalRead < 4 {
            let n = header.withUnsafeMutableBytes { ptr in
                read(fd, ptr.baseAddress! + totalRead, 4 - totalRead)
            }
            if n <= 0 { return }
            totalRead += n
        }

        guard let payloadLen = MessageFraming.decodeHeader(from: header), payloadLen <= 1024 * 1024 else {
            return
        }

        var payload = Data(count: Int(payloadLen))
        var payloadRead = 0
        while payloadRead < Int(payloadLen) {
            let n = payload.withUnsafeMutableBytes { ptr in
                read(fd, ptr.baseAddress! + payloadRead, Int(payloadLen) - payloadRead)
            }
            if n <= 0 { return }
            payloadRead += n
        }

        guard let message = try? JSONDecoder().decode(BridgeMessage.self, from: payload) else {
            let errorRes = BridgeResponse(id: "unknown", ok: false, reason: "Malformed message")
            if let errData = try? JSONEncoder().encode(errorRes) {
                let framed = MessageFraming.encode(errData)
                _ = framed.withUnsafeBytes { ptr in write(fd, ptr.baseAddress, framed.count) }
            }
            return
        }

        Task {
            let response = await self.delegate?.handleBridgeMessage(message) ?? BridgeResponse(id: message.id, ok: true)
            if let resData = try? JSONEncoder().encode(response) {
                let framed = MessageFraming.encode(resData)
                _ = framed.withUnsafeBytes { ptr in write(fd, ptr.baseAddress, framed.count) }
            }
        }
    }
}

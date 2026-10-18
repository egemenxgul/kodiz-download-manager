import Foundation

public actor FileWriter {
    private let targetURL: URL
    public let tempURL: URL
    private var fileDescriptor: Int32 = -1
    private let totalBytes: Int64?

    public init(destinationDirectory: URL, fileName: String, totalBytes: Int64?) {
        self.targetURL = destinationDirectory.appendingPathComponent(fileName)
        self.tempURL = destinationDirectory.appendingPathComponent("\(fileName).kodizpart")
        self.totalBytes = totalBytes
    }

    public func open() throws {
        let path = tempURL.path

        // Open or create with rw permissions (0644)
        let fd = Darwin.open(path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        self.fileDescriptor = fd

        // Preallocate if size is known using ftruncate for APFS sparse allocation
        if let total = totalBytes, total > 0 {
            ftruncate(fd, off_t(total))
        }
    }

    /// Thread-safe write to arbitrary offset using pwrite
    public func write(data: Data, at offset: Int64) throws {
        guard fileDescriptor >= 0 else {
            throw POSIXError(.EBADF)
        }

        var bytesWritten = 0
        let totalCount = data.count

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            while bytesWritten < totalCount {
                let currentOffset = off_t(offset + Int64(bytesWritten))
                let remaining = totalCount - bytesWritten
                let n = pwrite(fileDescriptor, baseAddress.advanced(by: bytesWritten), remaining, currentOffset)

                if n < 0 {
                    let err = errno
                    if err == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
                }
                bytesWritten += n
            }
        }
    }

    /// Syncs file data to disk (checkpoint)
    public func sync() throws {
        guard fileDescriptor >= 0 else { return }
        if fsync(fileDescriptor) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Closes descriptor, flushes buffers, and atomically moves .kodizpart to targetURL
    public func finalize() throws -> URL {
        guard fileDescriptor >= 0 else {
            throw POSIXError(.EBADF)
        }

        _ = fsync(fileDescriptor)
        close(fileDescriptor)
        fileDescriptor = -1

        // Never replace a file that appeared at the target meanwhile: pick "name (1).ext" instead
        let destDir = targetURL.deletingLastPathComponent()
        let finalName = FileNameParser.uniqueFileName(destDir: destDir, preferredName: targetURL.lastPathComponent, includeTempFiles: false)
        let finalURL = destDir.appendingPathComponent(finalName)

        try FileManager.default.moveItem(at: tempURL, to: finalURL)
        return finalURL
    }

    /// Truncates the temp file (unknown-length downloads restarted from byte 0)
    public func truncate(to length: Int64) throws {
        guard fileDescriptor >= 0 else { throw POSIXError(.EBADF) }
        if ftruncate(fileDescriptor, off_t(length)) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    public func closeWithoutFinalizing() {
        if fileDescriptor >= 0 {
            _ = fsync(fileDescriptor)
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    /// Deletes the temporary .kodizpart file (called upon cancel)
    public func deleteTempFile() {
        closeWithoutFinalizing()
        try? FileManager.default.removeItem(at: tempURL)
    }

    deinit {
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
        }
    }
}

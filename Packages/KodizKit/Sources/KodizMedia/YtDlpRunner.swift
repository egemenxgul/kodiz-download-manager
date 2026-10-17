import Foundation
import KodizBridgeProtocol

public protocol YtDlpRunnerDelegate: AnyObject, Sendable {
    func ytDlpDidUpdateProgress(_ progress: MediaProgress) async
    func ytDlpDidComplete(finalPath: String) async
    func ytDlpDidFail(error: Error, advice: String?) async
}

public actor YtDlpRunner {
    private let ytDlpBinaryPath: String
    private let ffmpegLocation: String?
    private let jsRuntimePath: String?
    private var process: Process?
    private weak var delegate: YtDlpRunnerDelegate?

    public init(
        ytDlpBinaryPath: String,
        ffmpegLocation: String? = nil,
        jsRuntimePath: String? = nil,
        delegate: YtDlpRunnerDelegate? = nil
    ) {
        self.ytDlpBinaryPath = ytDlpBinaryPath
        self.ffmpegLocation = ffmpegLocation
        self.jsRuntimePath = jsRuntimePath
        self.delegate = delegate
    }

    public func executeDownload(
        url: String,
        destDirectory: URL,
        tempDirectory: URL,
        cookiesFile: URL? = nil,
        userAgent: String? = nil,
        referer: String? = nil,
        formatSpec: String? = "res:1080,vcodec:h264,ext:mp4:m4a",
        rateLimit: Int64? = nil
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpBinaryPath)

        var args: [String] = ["--no-config"]

        if let ffmpeg = ffmpegLocation {
            args.append(contentsOf: ["--ffmpeg-location", ffmpeg])
        }

        if let qjs = jsRuntimePath {
            args.append(contentsOf: ["--js-runtimes", "quickjs:\(qjs)"])
        }

        if let format = formatSpec {
            args.append(contentsOf: ["-S", format])
        }

        args.append(contentsOf: [
            "--merge-output-format", "mp4",
            "-N", "4",
            "--newline",
            "--progress-template", "download:KDM %(progress)j",
            "--print", "after_move:KDMFILE %(filepath)s",
            "--no-playlist",
            "-P", destDirectory.path,
            "-P", "temp:\(tempDirectory.path)",
            "-o", "%(title).200B [%(id)s].%(ext)s"
        ])

        if let cookiePath = cookiesFile?.path {
            args.append(contentsOf: ["--cookies", cookiePath])
        }

        if let ua = userAgent {
            args.append(contentsOf: ["--user-agent", ua])
        }

        if let ref = referer {
            args.append(contentsOf: ["--referer", ref])
        }

        if let limit = rateLimit, limit > 0 {
            args.append(contentsOf: ["--limit-rate", "\(limit)"])
        }

        // Never shell, safe array, delimiter before URL
        args.append("--")
        args.append(url)

        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        self.process = process

        try process.run()

        let handle = pipe.fileHandleForReading

        Task.detached { [weak self, handle] in
            var buffer = Data()
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)

                while let newlineRange = buffer.range(of: Data([0x0A])) { // \n
                    let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                    buffer.removeSubrange(0...newlineRange.lowerBound)
                    if let line = String(data: lineData, encoding: .utf8) {
                        let parsed = MediaProgressParser.parseLine(line)
                        if let progress = parsed.progress {
                            await self?.notifyProgress(progress)
                        }
                        if let finalPath = parsed.finalPath {
                            await self?.notifyComplete(finalPath: finalPath)
                        }
                        if let advice = parsed.errorAdvice {
                            await self?.notifyAdvice(advice)
                        }
                    }
                }
            }
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let error = NSError(domain: "dev.kodiz.yt-dlp", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "yt-dlp process exited with code \(process.terminationStatus)"
            ])
            await delegate?.ytDlpDidFail(error: error, advice: nil)
        }
    }

    private func notifyProgress(_ progress: MediaProgress) async {
        await delegate?.ytDlpDidUpdateProgress(progress)
    }

    private func notifyComplete(finalPath: String) async {
        await delegate?.ytDlpDidComplete(finalPath: finalPath)
    }

    private func notifyAdvice(_ advice: String) async {
        let err = NSError(domain: "dev.kodiz.yt-dlp", code: 400, userInfo: [NSLocalizedDescriptionKey: advice])
        await delegate?.ytDlpDidFail(error: err, advice: advice)
    }

    public func pauseOrCancel() {
        if let proc = process, proc.isRunning {
            // Send SIGINT to allow graceful cleanup
            kill(proc.processIdentifier, SIGINT)
        }
    }
}

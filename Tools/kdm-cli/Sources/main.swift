import Foundation
import KodizEngine
import KodizSystem

struct CheckpointData: Codable {
    let id: UUID
    let url: URL
    let destinationDirectory: URL
    let fileName: String
    let totalBytes: Int64?
    let segments: [Segment]
}

final class CLIDownloadDelegate: DownloadEngineDelegate, @unchecked Sendable {
    private let startTime = Date()
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func downloadDidUpdateProgress(_ progress: DownloadProgress) async {
        let speedMB = progress.speed / (1024 * 1024)
        let downloadedMB = Double(progress.downloadedBytes) / (1024 * 1024)
        let totalStr: String
        if let total = progress.totalBytes {
            let totalMB = Double(total) / (1024 * 1024)
            totalStr = String(format: "%.1f / %.1f MB (%.1f%%)", downloadedMB, totalMB, progress.percentage)
        } else {
            totalStr = String(format: "%.1f MB", downloadedMB)
        }

        let segStates = progress.segments.map { s -> String in
            switch s.state {
            case .completed: return "█"
            case .downloading: return "▒"
            case .pending: return "░"
            case .failed: return "!"
            }
        }.joined()

        print("\r[\(segStates)] \(totalStr) | \(String(format: "%.2f MB/s", speedMB))   ", terminator: "")
        fflush(stdout)
    }

    func downloadDidComplete(finalURL: URL) async {
        let elapsed = Date().timeIntervalSince(startTime)
        print("\n\n✓ Download completed in \(String(format: "%.2f", elapsed))s!")
        print("Saved to: \(finalURL.path)")

        // Plan §4.7 / Requirement m: Apply metadata at application/tool level
        FileMetadata.applyQuarantine(to: finalURL)
        FileMetadata.applyWhereFroms(to: finalURL, originalURL: url.absoluteString, referer: nil)
        FileMetadata.notifyDockDownloadsBounce(fileURL: finalURL)

        exit(0)
    }

    func downloadDidFail(error: Error) async {
        print("\n\n✗ Download failed: \(error.localizedDescription)")
        exit(1)
    }
}

@main
struct KDMCLI {
    static func main() async {
        let args = CommandLine.arguments

        guard args.count >= 2 else {
            printUsage()
            return
        }

        let command = args[1]
        if command == "get" {
            await handleGet(args: args)
        } else if command == "resume" {
            await handleResume(args: args)
        } else {
            printUsage()
        }
    }

    static func handleGet(args: [String]) async {
        guard args.count >= 3, let url = URL(string: args[2]) else {
            print("Error: Valid URL required.")
            return
        }

        var connections = 8
        var destDir = FileManager.default.currentDirectoryPath
        var pauseAfter: TimeInterval? = nil
        var checkpointPath: String? = nil

        var i = 3
        while i < args.count {
            if args[i] == "-c" && i + 1 < args.count {
                connections = Int(args[i + 1]) ?? 8
                i += 2
            } else if args[i] == "-o" && i + 1 < args.count {
                destDir = args[i + 1]
                i += 2
            } else if args[i] == "--pause-after" && i + 1 < args.count {
                pauseAfter = Double(args[i + 1])
                i += 2
            } else if args[i] == "--checkpoint-file" && i + 1 < args.count {
                checkpointPath = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        print("=== Kodiz Download Manager CLI ===")
        print("URL: \(url.absoluteString)")
        print("Connections: \(connections)")
        print("Destination: \(destDir)")
        if let pause = pauseAfter {
            print("Pause after: \(pause)s")
        }

        let destURL = URL(fileURLWithPath: destDir)
        let delegate = CLIDownloadDelegate(url: url)
        let engine = DownloadEngine(
            url: url,
            destinationDirectory: destURL,
            delegate: delegate
        )

        if let pauseSec = pauseAfter {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(pauseSec * 1_000_000_000))
                print("\n\n[CLI] Pausing download as requested...")
                let segments = await engine.pause()
                let total = await engine.totalBytes
                let fileName = await engine.fileName
                let id = await engine.id

                let ckData = CheckpointData(
                    id: id,
                    url: url,
                    destinationDirectory: destURL,
                    fileName: fileName,
                    totalBytes: total,
                    segments: segments
                )

                let savePath = checkpointPath ?? "\(destDir)/\(fileName).checkpoint.json"
                if let jsonData = try? JSONEncoder().encode(ckData) {
                    try? jsonData.write(to: URL(fileURLWithPath: savePath))
                    print("[CLI] Checkpoint saved to: \(savePath)")
                }
                exit(0)
            }
        }

        do {
            try await engine.start(connections: connections)
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch {
            print("Failed to start download: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func handleResume(args: [String]) async {
        guard args.count >= 3 else {
            print("Error: Checkpoint file path required.")
            return
        }

        let checkpointPath = args[2]
        var connections = 8

        var i = 3
        while i < args.count {
            if args[i] == "-c" && i + 1 < args.count {
                connections = Int(args[i + 1]) ?? 8
                i += 2
            } else {
                i += 1
            }
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: checkpointPath)),
              let ck = try? JSONDecoder().decode(CheckpointData.self, from: data) else {
            print("Error: Failed to read or parse checkpoint file at \(checkpointPath)")
            exit(1)
        }

        print("=== Kodiz Download Manager CLI (Resume) ===")
        print("URL: \(ck.url.absoluteString)")
        print("Resuming file: \(ck.fileName)")
        print("Destination: \(ck.destinationDirectory.path)")
        print("Connections: \(connections)")

        let delegate = CLIDownloadDelegate(url: ck.url)
        let engine = DownloadEngine(
            id: ck.id,
            url: ck.url,
            destinationDirectory: ck.destinationDirectory,
            preferredFileName: ck.fileName,
            delegate: delegate
        )

        do {
            try await engine.start(connections: connections, existingSegments: ck.segments)
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch {
            print("Failed to resume download: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        Usage:
          kdm-cli get <url> [-c connections] [-o destDir] [--pause-after <sec>] [--checkpoint-file <path>]
          kdm-cli resume <checkpoint-file> [-c connections]

        Options:
          -c                     Number of parallel connections (default: 8)
          -o                     Destination directory (default: current directory)
          --pause-after <sec>    Pause download after given seconds and save checkpoint
          --checkpoint-file <p>  Path to save checkpoint file
        """)
    }
}

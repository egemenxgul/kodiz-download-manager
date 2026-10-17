import Foundation
import KodizEngine
import KodizSystem

final class CLIDownloadDelegate: DownloadEngineDelegate, @unchecked Sendable {
    private let startTime = Date()

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
        if command != "get" {
            printUsage()
            return
        }

        guard args.count >= 3, let url = URL(string: args[2]) else {
            print("Error: Valid URL required.")
            return
        }

        var connections = 8
        var destDir = FileManager.default.currentDirectoryPath

        var i = 3
        while i < args.count {
            if args[i] == "-c" && i + 1 < args.count {
                connections = Int(args[i + 1]) ?? 8
                i += 2
            } else if args[i] == "-o" && i + 1 < args.count {
                destDir = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        print("=== Kodiz Download Manager CLI ===")
        print("URL: \(url.absoluteString)")
        print("Connections: \(connections)")
        print("Destination: \(destDir)")
        print("Probing server...")

        let destURL = URL(fileURLWithPath: destDir)
        let delegate = CLIDownloadDelegate()
        let engine = DownloadEngine(
            url: url,
            destinationDirectory: destURL,
            delegate: delegate
        )

        do {
            try await engine.start(connections: connections)
            // Keep process alive while downloading
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch {
            print("Failed to start download: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        Usage:
          kdm-cli get <url> [-c connections] [-o destDir]

        Options:
          -c    Number of parallel connections (default: 8)
          -o    Destination directory (default: current directory)

        Example:
          kdm-cli get https://example.com/largefile.zip -c 8
        """)
    }
}

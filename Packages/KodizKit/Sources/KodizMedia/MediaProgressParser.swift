import Foundation

public enum MediaDownloadStage: String, Sendable {
    case preparing
    case downloadingVideo
    case downloadingAudio
    case merging
    case extractingAudio
    case completed
    case failed
}

public struct MediaProgress: Sendable {
    public let stage: MediaDownloadStage
    public let downloadedBytes: Int64
    public let totalBytes: Int64?
    public let speed: Double
    public let eta: Int?
    public let fragmentIndex: Int?
    public let fragmentCount: Int?
    public let rawMessage: String

    public var percentage: Double {
        guard let total = totalBytes, total > 0 else { return 0.0 }
        return min(100.0, (Double(downloadedBytes) / Double(total)) * 100.0)
    }
}

public enum MediaProgressParser {
    public static func parseLine(_ line: String) -> (progress: MediaProgress?, finalPath: String?, errorAdvice: String?) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Final file output
        if trimmed.hasPrefix("after_move:KDMFILE ") {
            let path = String(trimmed.dropFirst("after_move:KDMFILE ".count)).trimmingCharacters(in: .whitespaces)
            return (nil, path, nil)
        }

        // 2. JSON Progress
        if trimmed.hasPrefix("download:KDM ") {
            let jsonString = String(trimmed.dropFirst("download:KDM ".count))
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let downloaded = (json["downloaded_bytes"] as? NSNumber)?.int64Value ?? 0
                let total = (json["total_bytes"] as? NSNumber)?.int64Value ?? (json["total_bytes_estimate"] as? NSNumber)?.int64Value
                let speed = (json["speed"] as? NSNumber)?.doubleValue ?? 0.0
                let eta = (json["eta"] as? NSNumber)?.intValue
                let fragIndex = (json["fragment_index"] as? NSNumber)?.intValue
                let fragCount = (json["fragment_count"] as? NSNumber)?.intValue

                let progress = MediaProgress(
                    stage: .downloadingVideo,
                    downloadedBytes: downloaded,
                    totalBytes: total,
                    speed: speed,
                    eta: eta,
                    fragmentIndex: fragIndex,
                    fragmentCount: fragCount,
                    rawMessage: trimmed
                )
                return (progress, nil, nil)
            }
        }

        // 3. Stage changes
        if trimmed.contains("[Merger]") {
            let progress = MediaProgress(stage: .merging, downloadedBytes: 0, totalBytes: nil, speed: 0, eta: nil, fragmentIndex: nil, fragmentCount: nil, rawMessage: trimmed)
            return (progress, nil, nil)
        }

        if trimmed.contains("[ExtractAudio]") {
            let progress = MediaProgress(stage: .extractingAudio, downloadedBytes: 0, totalBytes: nil, speed: 0, eta: nil, fragmentIndex: nil, fragmentCount: nil, rawMessage: trimmed)
            return (progress, nil, nil)
        }

        // 4. Known Error & Advice Mapping (PLAN.md §8.3)
        var advice: String?
        if trimmed.localizedCaseInsensitiveContains("Sign in to confirm your age") {
            advice = "Giriş yapmanız veya tarayıcı çerezlerini aktarmanız gerekiyor."
        } else if trimmed.localizedCaseInsensitiveContains("confirm you're not a bot") {
            advice = "Bot koruması algılandı. Lütfen tarayıcı çerezlerini kullanın."
        } else if trimmed.localizedCaseInsensitiveContains("HTTP Error 403") {
            advice = "HTTP 403 hatası: yt-dlp güncellemesi gerekebilir."
        } else if trimmed.localizedCaseInsensitiveContains("Requested format is not available") {
            advice = "İstenen format mevcut değil. Lütfen format seçiciyi açın."
        } else if trimmed.localizedCaseInsensitiveContains("DRM") {
            advice = "Bu içerik DRM korumalıdır ve indirilemez."
        }

        return (nil, nil, advice)
    }
}

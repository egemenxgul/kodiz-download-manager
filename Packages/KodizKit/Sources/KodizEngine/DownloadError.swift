import Foundation

public enum DownloadError: Error, Sendable, LocalizedError, Equatable {
    case fileChanged
    case invalidURL(String)
    case diskFull(String)
    case accessDenied(String)
    case resourceNotFound // 404
    case gone // 410
    case unauthorized // 401
    case forbidden // 403
    case rangeNotSatisfiable // 416
    case maxAttemptsExceeded(segmentIdx: Int)
    case serverError(statusCode: Int)
    case serverDoesNotSupportRange
    case networkError(String)
    case cancelled
    case badServerResponse(String)
    case checksumMismatch(expected: String, actual: String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .fileChanged:
            return "Dosya sunucuda değişmiş (ETag/If-Range uyuşmazlığı)."
        case .invalidURL(let u):
            return "Geçersiz URL: \(u)"
        case .diskFull(let msg):
            return "Disk dolu (ENOSPC): \(msg)"
        case .accessDenied(let msg):
            return "Erişim engellendi (EACCES): \(msg)"
        case .resourceNotFound:
            return "Dosya bulunamadı (HTTP 404)."
        case .gone:
            return "Kaynak artık mevcut değil (HTTP 410)."
        case .unauthorized:
            return "Yetkilendirme gerekli (HTTP 401)."
        case .forbidden:
            return "Erişim yasak (HTTP 403)."
        case .rangeNotSatisfiable:
            return "Range aralığı geçersiz (HTTP 416)."
        case .maxAttemptsExceeded(let idx):
            return "Parça \(idx) için en fazla deneme sayısı (10) aşıldı."
        case .serverError(let code):
            return "Sunucu hatası: HTTP \(code)."
        case .serverDoesNotSupportRange:
            return "Sunucu Range desteği sağlamıyor."
        case .networkError(let msg):
            return "Ağ hatası: \(msg)"
        case .cancelled:
            return "İndirme iptal edildi."
        case .badServerResponse(let msg):
            return "Sunucudan geçersiz yanıt: \(msg)"
        case .checksumMismatch(let exp, let act):
            return "Sağlama toplamı uyuşmuyor: beklenen \(exp), hesaplanan \(act)."
        case .unknown(let msg):
            return "Bilinmeyen hata: \(msg)"
        }
    }

    public var isPermanent: Bool {
        switch self {
        case .resourceNotFound, .gone, .unauthorized, .forbidden, .rangeNotSatisfiable, .diskFull, .accessDenied, .fileChanged, .maxAttemptsExceeded:
            return true
        default:
            return false
        }
    }
}

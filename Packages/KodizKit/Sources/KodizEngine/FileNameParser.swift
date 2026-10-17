import Foundation
import UniformTypeIdentifiers

public enum FileNameParser {
    /// Extracts and sanitizes the file name according to RFC 6266 / RFC 5987, URL path, and MIME fallback.
    public static func resolveFileName(
        contentDisposition: String?,
        url: URL,
        mimeType: String?
    ) -> String {
        var rawName: String?

        if let cd = contentDisposition {
            rawName = parseContentDisposition(cd)
        }

        if rawName == nil || rawName!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lastComponent = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
            if !lastComponent.isEmpty && lastComponent != "/" {
                rawName = lastComponent
            }
        }

        if rawName == nil || rawName!.isEmpty || rawName == "/" {
            rawName = "download"
        }

        var sanitized = sanitize(rawName!)

        // If file has no extension and we have a MIME type, append suitable extension
        if (sanitized as NSString).pathExtension.isEmpty, let mime = mimeType {
            if let utType = UTType(mimeType: mime), let preferredExt = utType.preferredFilenameExtension {
                sanitized = "\(sanitized).\(preferredExt)"
            }
        }

        return sanitized
    }

    /// Parses Content-Disposition header supporting filename* (RFC 5987) and filename="..."
    public static func parseContentDisposition(_ header: String) -> String? {
        // Priority 1: filename*=UTF-8''encoded_name
        if let match = header.range(of: "filename\\*\\s*=\\s*([^;]+)", options: .regularExpression) {
            let value = String(header[match])
                .replacingOccurrences(of: "^filename\\*\\s*=\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))

            // Format: UTF-8''encoded_string
            let parts = value.components(separatedBy: "''")
            if parts.count == 2 {
                let encoded = parts[1]
                if let decoded = encoded.removingPercentEncoding {
                    return decoded
                }
            } else if let decoded = value.removingPercentEncoding {
                return decoded
            }
        }

        // Priority 2: filename="name" or filename=name
        if let match = header.range(of: "filename\\s*=\\s*([^;]+)", options: .regularExpression) {
            var value = String(header[match])
                .replacingOccurrences(of: "^filename\\s*=\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value.removingPercentEncoding ?? value
        }

        return nil
    }

    /// Sanitizes file names: strips invalid characters (:, /), control chars, limits length to 255 bytes, NFC normalization
    public static func sanitize(_ fileName: String) -> String {
        var clean = fileName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")

        // Remove non-printable control characters
        clean = clean.components(separatedBy: .controlCharacters).joined()
        clean = clean.precomposedStringWithCanonicalMapping // NFC

        if clean.isEmpty {
            clean = "download"
        }

        // Enforce max 255 bytes preserving extension
        let ext = (clean as NSString).pathExtension
        let base = (clean as NSString).deletingPathExtension

        let maxByteLength = 255
        let extWithDot = ext.isEmpty ? "" : ".\(ext)"
        let extBytes = extWithDot.utf8.count

        if clean.utf8.count > maxByteLength {
            let maxBaseBytes = max(1, maxByteLength - extBytes)
            var truncatedBase = ""
            var currentBytes = 0
            for char in base {
                let charBytes = String(char).utf8.count
                if currentBytes + charBytes > maxBaseBytes { break }
                truncatedBase.append(char)
                currentBytes += charBytes
            }
            clean = "\(truncatedBase)\(extWithDot)"
        }

        return clean
    }

    /// Generates next collision-free name: "name (1).ext"
    public static func uniqueFileName(destDir: URL, preferredName: String) -> String {
        let fileManager = FileManager.default
        let ext = (preferredName as NSString).pathExtension
        let base = (preferredName as NSString).deletingPathExtension
        let extSuffix = ext.isEmpty ? "" : ".\(ext)"

        var candidate = preferredName
        var counter = 1

        while fileManager.fileExists(atPath: destDir.appendingPathComponent(candidate).path) {
            candidate = "\(base) (\(counter))\(extSuffix)"
            counter += 1
        }

        return candidate
    }
}

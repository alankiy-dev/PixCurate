import Foundation
import ImageIO

enum EXIFService {

    /// Read shooting date from EXIF without decoding the full image (fast, sandbox-safe)
    nonisolated static func readShotDate(url: URL) -> Date? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
            let props  = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let exif   = props[kCGImagePropertyExifDictionary as String] as? [String: Any],
            let raw    = (exif[kCGImagePropertyExifDateTimeOriginal as String]
                       ?? exif[kCGImagePropertyExifDateTimeDigitized as String]) as? String
        else { return nil }
        return parseExifDate(raw)
    }

    /// Parse EXIF date string "yyyy:MM:dd HH:mm:ss" without DateFormatter (nonisolated-safe)
    nonisolated private static func parseExifDate(_ s: String) -> Date? {
        let parts = s.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let d = parts[0].split(separator: ":")
        let t = parts[1].split(separator: ":")
        guard d.count == 3, t.count == 3 else { return nil }
        var c = DateComponents()
        c.year   = Int(d[0]); c.month  = Int(d[1]); c.day    = Int(d[2])
        c.hour   = Int(t[0]); c.minute = Int(t[1]); c.second = Int(t[2])
        return Calendar.current.date(from: c)
    }
}

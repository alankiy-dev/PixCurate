import Foundation
import ImageIO

// MARK: - EXIFInfo

struct EXIFInfo: Sendable {
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: Double?
    var aperture: Double?
    var shutterSpeed: Double?
    var iso: Int?
    var shotDate: Date?
    var imageWidth: Int?
    var imageHeight: Int?
}

// MARK: - EXIFService

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

    /// Read full EXIF info (camera, lens, exposure, resolution)
    nonisolated static func readEXIFInfo(url: URL) -> EXIFInfo {
        var info = EXIFInfo()
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
            let props  = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return info }

        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        info.cameraMake   = tiff?[kCGImagePropertyTIFFMake as String] as? String
        info.cameraModel  = tiff?[kCGImagePropertyTIFFModel as String] as? String
        info.lensModel    = exif?[kCGImagePropertyExifLensModel as String] as? String
        info.focalLength  = exif?[kCGImagePropertyExifFocalLength as String] as? Double
        info.aperture     = exif?[kCGImagePropertyExifFNumber as String] as? Double
        info.shutterSpeed = exif?[kCGImagePropertyExifExposureTime as String] as? Double
        info.imageWidth   = props[kCGImagePropertyPixelWidth as String] as? Int
        info.imageHeight  = props[kCGImagePropertyPixelHeight as String] as? Int

        if let isos = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int] {
            info.iso = isos.first
        }
        if let raw = (exif?[kCGImagePropertyExifDateTimeOriginal as String]
                   ?? exif?[kCGImagePropertyExifDateTimeDigitized as String]) as? String {
            info.shotDate = parseExifDate(raw)
        }
        return info
    }

    /// Parse EXIF date string "yyyy:MM:dd HH:mm:ss" without DateFormatter (nonisolated-safe)
    nonisolated static func parseExifDate(_ s: String) -> Date? {
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

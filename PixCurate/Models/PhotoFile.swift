import Foundation
import SwiftUI

// MARK: - ColorLabel

enum ColorLabel: String, CaseIterable, Sendable {
    case red    = "Red"
    case yellow = "Yellow"
    case green  = "Green"
    case blue   = "Blue"
    case purple = "Purple"

    var color: Color {
        switch self {
        case .red:    return Color(red: 0.95, green: 0.25, blue: 0.25)
        case .yellow: return Color(red: 0.95, green: 0.80, blue: 0.10)
        case .green:  return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .blue:   return Color(red: 0.20, green: 0.50, blue: 0.95)
        case .purple: return Color(red: 0.65, green: 0.25, blue: 0.90)
        }
    }

    var keyChar: Character {
        switch self {
        case .red:    return "r"
        case .yellow: return "y"
        case .green:  return "g"
        case .blue:   return "b"
        case .purple: return "p"
        }
    }

    var localizedName: String {
        switch self {
        case .red:    return "赤"
        case .yellow: return "黄"
        case .green:  return "緑"
        case .blue:   return "青"
        case .purple: return "紫"
        }
    }
}

// MARK: - PhotoFile

struct PhotoFile: Identifiable, Sendable {
    let id: UUID
    let rawURL: URL
    var rating: Int?
    var shotDate: Date?
    var tags: [String] = []
    var locationPath: LocationPath? = nil
    var locationId: UUID? = nil
    var xmpModifiedAt: Date? = nil
    var isOffline: Bool = false
    var colorLabel: ColorLabel? = nil

    nonisolated init(rawURL: URL) {
        self.id = UUID()
        self.rawURL = rawURL
    }

    nonisolated var xmpURL: URL {
        rawURL.deletingPathExtension().appendingPathExtension("xmp")
    }
    nonisolated var filename: String { rawURL.lastPathComponent }
    nonisolated var fileExtension: String { rawURL.pathExtension.uppercased() }
    nonisolated var isJpeg: Bool {
        let ext = rawURL.pathExtension.lowercased()
        return ext == "jpg" || ext == "jpeg"
    }
}

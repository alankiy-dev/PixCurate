import Foundation
import Observation
import SwiftUI

// MARK: - ListColumn

enum ListColumn: String, CaseIterable, Identifiable {
    // DB items (instant)
    case shotDate     = "shotDate"
    case rating       = "rating"
    case location     = "location"
    case tags         = "tags"
    case xmpDate      = "xmpDate"
    // EXIF items (async, read from file)
    case camera       = "camera"
    case lens         = "lens"
    case focalLength  = "focalLength"
    case aperture     = "aperture"
    case shutterSpeed = "shutterSpeed"
    case iso          = "iso"
    case resolution   = "resolution"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shotDate:     return "撮影日時"
        case .rating:       return "★評価"
        case .location:     return "撮影地"
        case .tags:         return "タグ"
        case .xmpDate:      return "XMP更新日"
        case .camera:       return "カメラ"
        case .lens:         return "レンズ"
        case .focalLength:  return "焦点距離"
        case .aperture:     return "絞り"
        case .shutterSpeed: return "SS"
        case .iso:          return "ISO"
        case .resolution:   return "解像度"
        }
    }

    var needsEXIF: Bool {
        switch self {
        case .camera, .lens, .focalLength, .aperture, .shutterSpeed, .iso, .resolution:
            return true
        default:
            return false
        }
    }

    var columnWidth: CGFloat {
        switch self {
        case .shotDate:     return 130
        case .rating:       return 48
        case .location:     return 90
        case .tags:         return 115
        case .xmpDate:      return 130
        case .camera:       return 155
        case .lens:         return 165
        case .focalLength:  return 58
        case .aperture:     return 65
        case .shutterSpeed: return 68
        case .iso:          return 65
        case .resolution:   return 98
        }
    }

    /// Excel 列幅（文字単位）
    var xlsxWidth: Double {
        switch self {
        case .shotDate:     return 20
        case .rating:       return 12
        case .location:     return 18
        case .tags:         return 22
        case .xmpDate:      return 20
        case .camera:       return 28
        case .lens:         return 32
        case .focalLength:  return 13
        case .aperture:     return 8
        case .shutterSpeed: return 10
        case .iso:          return 7
        case .resolution:   return 14
        }
    }
}

// MARK: - List layout constants (shared between header and row)
enum ListLayout {
    static let thumbWidth:  CGFloat = 80
    static let thumbHeight: CGFloat = 52
    static let thumbGap:    CGFloat = 8    // explicit spacer between thumb and filename
    static let rowHPad:     CGFloat = 8    // outer horizontal padding for both header and rows
    static let rowVPad:     CGFloat = 3
    // Total leading fixed space before filename (thumb + gap)
    static let rowLeading: CGFloat = thumbWidth + thumbGap  // 88
}

// MARK: - DisplaySettings

@Observable
final class DisplaySettings {

    static let shared = DisplaySettings()

    // MARK: - View mode
    enum ViewMode: String, CaseIterable {
        case grid = "グリッド"
        case list = "リスト"
    }
    var viewMode: ViewMode = .grid

    // MARK: - Overlay badges (on thumbnail)
    var showRating: Bool   = true
    var showTags: Bool     = true
    var showLocation: Bool = true

    // MARK: - Info below thumbnail
    var showFilename: Bool  = true
    var showShotDate: Bool  = true

    // MARK: - Thumbnail size
    enum ThumbSize: String, CaseIterable {
        case small = "小"; case medium = "中"; case large = "大"
        var width: CGFloat   { switch self { case .small: 160; case .medium: 220; case .large: 300 } }
        var height: CGFloat  { switch self { case .small: 120; case .medium: 165; case .large: 225 } }
        var spacing: CGFloat { switch self { case .small: 10;  case .medium: 12;  case .large: 16  } }
        var maxPixel: Int    { switch self { case .small: 320; case .medium: 440; case .large: 600 } }
    }
    var thumbSize: ThumbSize = .small

    // MARK: - Badge font size (tags + location overlays)
    enum BadgeFont: String, CaseIterable {
        case small = "小"; case medium = "中"; case large = "大"
        var size: CGFloat { switch self { case .small: 8; case .medium: 10; case .large: 13 } }
    }
    var badgeFont: BadgeFont = .small

    // MARK: - List view columns
    var listColumns: Set<ListColumn> = [.shotDate, .rating, .location, .tags]

    // MARK: - Grid/List background color
    enum GridBackground: String, CaseIterable {
        case system = "自動"
        case white  = "白"
        case black  = "黒"

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .white:  return .light
            case .black:  return .dark
            }
        }
    }
    var gridBackground: GridBackground = .system

    // MARK: - Persistence

    private enum K {
        static let showRating      = "ds.showRating"
        static let showTags        = "ds.showTags"
        static let showLocation    = "ds.showLocation"
        static let showFilename    = "ds.showFilename"
        static let showShotDate    = "ds.showShotDate"
        static let thumbSize       = "ds.thumbSize"
        static let badgeFont       = "ds.badgeFont"
        static let viewMode        = "ds.viewMode"
        static let listColumns     = "ds.listColumns"
        static let gridBackground  = "ds.gridBackground"
    }

    init() { load() }

    private func load() {
        let d = UserDefaults.standard
        showRating      = d.object(forKey: K.showRating)   as? Bool ?? true
        showTags        = d.object(forKey: K.showTags)     as? Bool ?? true
        showLocation    = d.object(forKey: K.showLocation) as? Bool ?? true
        showFilename    = d.object(forKey: K.showFilename) as? Bool ?? true
        showShotDate    = d.object(forKey: K.showShotDate) as? Bool ?? true
        thumbSize       = ThumbSize(rawValue: d.string(forKey: K.thumbSize) ?? "") ?? .small
        badgeFont       = BadgeFont(rawValue: d.string(forKey: K.badgeFont) ?? "") ?? .small
        viewMode        = ViewMode(rawValue:  d.string(forKey: K.viewMode)  ?? "") ?? .grid
        gridBackground  = GridBackground(rawValue: d.string(forKey: K.gridBackground) ?? "") ?? .system
        if let str = d.string(forKey: K.listColumns) {
            listColumns = Set(str.split(separator: ",").compactMap { ListColumn(rawValue: String($0)) })
        }
    }

    func save() {
        let d = UserDefaults.standard
        d.set(showRating,              forKey: K.showRating)
        d.set(showTags,                forKey: K.showTags)
        d.set(showLocation,            forKey: K.showLocation)
        d.set(showFilename,            forKey: K.showFilename)
        d.set(showShotDate,            forKey: K.showShotDate)
        d.set(thumbSize.rawValue,      forKey: K.thumbSize)
        d.set(badgeFont.rawValue,      forKey: K.badgeFont)
        d.set(viewMode.rawValue,       forKey: K.viewMode)
        d.set(gridBackground.rawValue, forKey: K.gridBackground)
        d.set(listColumns.map(\.rawValue).joined(separator: ","), forKey: K.listColumns)
    }
}

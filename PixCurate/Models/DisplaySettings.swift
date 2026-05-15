import Foundation
import Observation

@Observable
final class DisplaySettings {

    static let shared = DisplaySettings()

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

    // MARK: - Persistence

    private enum K {
        static let showRating   = "ds.showRating"
        static let showTags     = "ds.showTags"
        static let showLocation = "ds.showLocation"
        static let showFilename = "ds.showFilename"
        static let showShotDate = "ds.showShotDate"
        static let thumbSize    = "ds.thumbSize"
        static let badgeFont    = "ds.badgeFont"
    }

    init() { load() }

    private func load() {
        let d = UserDefaults.standard
        showRating   = d.object(forKey: K.showRating)   as? Bool ?? true
        showTags     = d.object(forKey: K.showTags)     as? Bool ?? true
        showLocation = d.object(forKey: K.showLocation) as? Bool ?? true
        showFilename = d.object(forKey: K.showFilename) as? Bool ?? true
        showShotDate = d.object(forKey: K.showShotDate) as? Bool ?? true
        thumbSize    = ThumbSize(rawValue:  d.string(forKey: K.thumbSize)  ?? "") ?? .small
        badgeFont    = BadgeFont(rawValue:  d.string(forKey: K.badgeFont)  ?? "") ?? .small
    }

    func save() {
        let d = UserDefaults.standard
        d.set(showRating,         forKey: K.showRating)
        d.set(showTags,           forKey: K.showTags)
        d.set(showLocation,       forKey: K.showLocation)
        d.set(showFilename,       forKey: K.showFilename)
        d.set(showShotDate,       forKey: K.showShotDate)
        d.set(thumbSize.rawValue, forKey: K.thumbSize)
        d.set(badgeFont.rawValue, forKey: K.badgeFont)
    }
}

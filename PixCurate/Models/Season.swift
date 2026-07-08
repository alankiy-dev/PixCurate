import Foundation
import Observation
import SwiftUI

// MARK: - Season（季節）

enum Season: String, CaseIterable, Codable, Identifiable {
    case spring
    case summer
    case autumn
    case winter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spring: return "春"
        case .summer: return "夏"
        case .autumn: return "秋"
        case .winter: return "冬"
        }
    }

    var symbol: String {
        switch self {
        case .spring: return "leaf.fill"
        case .summer: return "sun.max.fill"
        case .autumn: return "wind"
        case .winter: return "snowflake"
        }
    }

    var color: Color {
        switch self {
        case .spring: return .green
        case .summer: return .orange
        case .autumn: return .brown
        case .winter: return .cyan
        }
    }
}

// MARK: - SeasonSettings（季節ごとの月割り当て・設定で変更可能）

@Observable
final class SeasonSettings {
    static let shared = SeasonSettings()

    /// 月(1〜12) → 季節。各月はちょうど1つの季節に属する。
    private(set) var monthSeason: [Int: Season]

    private let key = "pixcurate.seasonMonths"

    /// 初期値：春 3-5 / 夏 6-8 / 秋 9-11 / 冬 12,1,2
    static var defaultMap: [Int: Season] {
        var m: [Int: Season] = [:]
        for mo in [3, 4, 5]    { m[mo] = .spring }
        for mo in [6, 7, 8]    { m[mo] = .summer }
        for mo in [9, 10, 11]  { m[mo] = .autumn }
        for mo in [12, 1, 2]   { m[mo] = .winter }
        return m
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            var m: [Int: Season] = [:]
            for (k, v) in dict {
                if let mo = Int(k), let s = Season(rawValue: v) { m[mo] = s }
            }
            // 欠けている月は初期値で補完
            for mo in 1...12 where m[mo] == nil { m[mo] = Self.defaultMap[mo] }
            monthSeason = m
        } else {
            monthSeason = Self.defaultMap
        }
    }

    /// 指定した月が属する季節
    func season(forMonth month: Int) -> Season? { monthSeason[month] }

    /// 指定した季節に属する月（昇順）
    func months(for season: Season) -> [Int] {
        (1...12).filter { monthSeason[$0] == season }
    }

    /// 指定した季節の集合に属する月の集合
    func months(forSeasons seasons: Set<Season>) -> Set<Int> {
        var result = Set<Int>()
        for s in seasons { result.formUnion(months(for: s)) }
        return result
    }

    func setSeason(_ season: Season, forMonth month: Int) {
        guard (1...12).contains(month) else { return }
        monthSeason[month] = season
        save()
    }

    func resetToDefault() {
        monthSeason = Self.defaultMap
        save()
    }

    private func save() {
        var dict: [String: String] = [:]
        for (mo, s) in monthSeason { dict[String(mo)] = s.rawValue }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

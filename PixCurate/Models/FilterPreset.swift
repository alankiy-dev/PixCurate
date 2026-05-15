import Foundation

struct FilterPreset: Identifiable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var minRating: Int
    var tagGroups: [[String]]   // outer=AND, inner=OR
    var locationIds: [UUID]
}

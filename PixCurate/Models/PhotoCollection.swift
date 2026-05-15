import Foundation

struct PhotoCollection: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var fileCount: Int = 0
}

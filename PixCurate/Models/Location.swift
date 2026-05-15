import Foundation

struct Location: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var parentId: UUID?

    init(id: UUID = UUID(), name: String, parentId: UUID? = nil) {
        self.id = id
        self.name = name
        self.parentId = parentId
    }
}

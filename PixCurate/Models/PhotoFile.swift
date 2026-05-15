import Foundation

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

    nonisolated init(rawURL: URL) {
        self.id = UUID()
        self.rawURL = rawURL
    }

    nonisolated var xmpURL: URL {
        rawURL.deletingPathExtension().appendingPathExtension("xmp")
    }
    nonisolated var filename: String { rawURL.lastPathComponent }
    nonisolated var fileExtension: String { rawURL.pathExtension.uppercased() }
}

import Foundation
import Observation

extension URL {
    /// /Volumes/VolumeName/... のボリューム名を返す。それ以外は nil
    var volumeName: String? {
        let parts = pathComponents
        guard parts.count >= 3, parts[1] == "Volumes" else { return nil }
        return parts[2]
    }
}

@Observable
final class CollectionStore {
    static let shared = CollectionStore()

    var collections: [PhotoCollection] = []

    private init() { load() }

    func load() {
        let rows = DatabaseService.shared.loadCollections()
        let fmt = ISO8601DateFormatter()
        collections = rows.map { row in
            PhotoCollection(
                id:        UUID(uuidString: row.id) ?? UUID(),
                name:      row.name,
                createdAt: fmt.date(from: row.createdAt) ?? Date(),
                fileCount: row.fileCount
            )
        }
    }

    @discardableResult
    func add(name: String) -> PhotoCollection {
        let col = PhotoCollection(id: UUID(), name: name, createdAt: Date(), fileCount: 0)
        DatabaseService.shared.insertCollection(id: col.id.uuidString, name: col.name)
        collections.append(col)
        return col
    }

    func rename(_ collection: PhotoCollection, to name: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[idx].name = name
        DatabaseService.shared.renameCollection(id: collection.id.uuidString, name: name)
    }

    func delete(_ collection: PhotoCollection) {
        collections.removeAll { $0.id == collection.id }
        DatabaseService.shared.deleteCollection(id: collection.id.uuidString)
    }

    func addFiles(_ files: [PhotoFile], to collection: PhotoCollection) {
        guard !files.isEmpty else { return }
        DatabaseService.shared.addFiles(paths: files.map(\.rawURL.path),
                                        toCollection: collection.id.uuidString)
        refreshCount(collection.id)
    }

    func removeFiles(_ files: [PhotoFile], from collection: PhotoCollection) {
        guard !files.isEmpty else { return }
        DatabaseService.shared.removeFiles(paths: files.map(\.rawURL.path),
                                           fromCollection: collection.id.uuidString)
        refreshCount(collection.id)
    }

    func filePaths(in collection: PhotoCollection) -> Set<String> {
        DatabaseService.shared.filePathsInCollection(collection.id.uuidString)
    }

    func loadFiles(in collection: PhotoCollection) -> [PhotoFile] {
        let paths = filePaths(in: collection)
        let rows = DatabaseService.shared.loadFiles(paths: paths)
        let locStore = LocationStore.shared
        let fm = FileManager.default
        return rows.map { row in
            var file = row.toPhotoFile()
            if let lid = file.locationId {
                file.locationPath = locStore.buildLocationPath(for: lid)
            }
            file.isOffline = !fm.fileExists(atPath: row.path)
            return file
        }
    }

    /// ボリューム別にオフラインファイルをグループ化して返す
    func offlineGroups(in files: [PhotoFile]) -> [(volume: String, count: Int)] {
        var groups: [String: Int] = [:]
        for file in files where file.isOffline {
            let key = file.rawURL.volumeName ?? file.rawURL.deletingLastPathComponent().path
            groups[key, default: 0] += 1
        }
        return groups.map { (volume: $0.key, count: $0.value) }.sorted { $0.volume < $1.volume }
    }

    func contains(filePath: String, collectionId: UUID) -> Bool {
        let paths = DatabaseService.shared.filePathsInCollection(collectionId.uuidString)
        return paths.contains(filePath)
    }

    private func refreshCount(_ id: UUID) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].fileCount = DatabaseService.shared.fileCountInCollection(id.uuidString)
    }
}

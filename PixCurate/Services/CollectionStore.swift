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
                fileCount: row.fileCount,
                parentId:  row.parentId.flatMap { UUID(uuidString: $0) }
            )
        }
    }

    @discardableResult
    func add(name: String, parentId: UUID? = nil) -> PhotoCollection {
        let col = PhotoCollection(id: UUID(), name: name, createdAt: Date(),
                                  fileCount: 0, parentId: parentId)
        DatabaseService.shared.insertCollection(id: col.id.uuidString, name: col.name,
                                                parentId: parentId?.uuidString)
        collections.append(col)
        return col
    }

    // MARK: - 階層（グループ）操作

    /// 指定ノードの直下の子コレクション（作成順）
    func children(of parentId: UUID?) -> [PhotoCollection] {
        collections
            .filter { $0.parentId == parentId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// 子を持つ（＝グループとして振る舞う）か
    func hasChildren(_ id: UUID) -> Bool {
        collections.contains { $0.parentId == id }
    }

    /// 指定コレクションとその全子孫の id（削除用）
    func descendantIds(of id: UUID) -> [UUID] {
        var result: [UUID] = [id]
        for child in collections where child.parentId == id {
            result.append(contentsOf: descendantIds(of: child.id))
        }
        return result
    }

    /// 親をたどって表示用パス（例: 風景写真 / 2027年度 / S部門）
    func path(of collection: PhotoCollection) -> String {
        var names: [String] = [collection.name]
        var current = collection
        while let pid = current.parentId,
              let parent = collections.first(where: { $0.id == pid }) {
            names.insert(parent.name, at: 0)
            current = parent
        }
        return names.joined(separator: " / ")
    }

    func rename(_ collection: PhotoCollection, to name: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[idx].name = name
        DatabaseService.shared.renameCollection(id: collection.id.uuidString, name: name)
    }

    func delete(_ collection: PhotoCollection) {
        // 子グループも含めてまとめて削除する
        let ids = descendantIds(of: collection.id)
        let idSet = Set(ids)
        collections.removeAll { idSet.contains($0.id) }
        for id in ids {
            DatabaseService.shared.deleteCollection(id: id.uuidString)
        }
    }

    func addFiles(_ files: [PhotoFile], to collection: PhotoCollection) {
        guard !files.isEmpty else { return }
        // 追加時点でアクセス可能なフォルダの bookmark を保存しておく。
        // これにより、後でコピー元構成が変わってもコレクションの実ファイルへアクセスできる。
        CollectionAccessStore.shared.registerFolders(for: files)
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

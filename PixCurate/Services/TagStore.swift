import Foundation
import Observation

@Observable
final class TagStore {
    static let shared = TagStore()

    var tags: [Tag] = []

    private let storageURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("PixCurate")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("tags.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Tag].self, from: data) else { return }
        tags = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tags) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    func addTag(name: String, parentId: UUID? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(where: { $0.name == trimmed }) else { return }
        tags.append(Tag(name: trimmed, parentId: parentId))
        save()
    }

    func removeTag(_ tag: Tag) {
        tags.removeAll { $0.id == tag.id || $0.parentId == tag.id }
        save()
    }

    func renameTag(_ tag: Tag, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let idx = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tags[idx].name = trimmed
        save()
    }
}

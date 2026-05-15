import Foundation
import Observation

@Observable
final class LocationStore {
    static let shared = LocationStore()

    var locations: [Location] = []
    private let storageURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("PixCurate")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("locations.json")
        load()
    }

    // MARK: - CRUD

    func addLocation(name: String, parentId: UUID? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        locations.append(Location(name: trimmed, parentId: parentId))
        save()
    }

    func removeLocation(_ location: Location) {
        let toRemove = descendants(of: location.id).union([location.id])
        locations.removeAll { toRemove.contains($0.id) }
        save()
    }

    func rename(_ location: Location, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let idx = locations.firstIndex(where: { $0.id == location.id }) else { return }
        locations[idx].name = trimmed
        save()
    }

    // MARK: - Tree helpers

    func children(of parentId: UUID?) -> [Location] {
        locations.filter { $0.parentId == parentId }
    }

    /// Root → … → location (root first)
    func path(of id: UUID) -> [Location] {
        var result: [Location] = []
        var currentId: UUID? = id
        while let cid = currentId, let loc = locations.first(where: { $0.id == cid }) {
            result.insert(loc, at: 0)
            currentId = loc.parentId
        }
        return result
    }

    func pathString(of id: UUID) -> String {
        path(of: id).map(\.name).joined(separator: " › ")
    }

    /// All descendant IDs (not including self)
    func descendants(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = []
        var queue = [id]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for child in locations.filter({ $0.parentId == current }) {
                result.insert(child.id)
                queue.append(child.id)
            }
        }
        return result
    }

    /// Self + all ancestor IDs (used for filter matching)
    func selfAndAncestors(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var currentId = locations.first(where: { $0.id == id })?.parentId
        while let cid = currentId {
            result.insert(cid)
            currentId = locations.first(where: { $0.id == cid })?.parentId
        }
        return result
    }

    /// Build LocationPath from a location's ancestry chain (province/city/sublocation)
    func buildLocationPath(for id: UUID) -> LocationPath {
        let chain = path(of: id).map(\.name)
        return LocationPath(
            province:    chain.indices.contains(0) ? chain[0] : nil,
            city:        chain.indices.contains(1) ? chain[1] : nil,
            sublocation: chain.indices.contains(2) ? chain[2] : nil
        )
    }

    /// Match XMP-read IPTC fields back to a location ID
    func match(path locationPath: LocationPath) -> UUID? {
        // Try most specific first
        if let sub = locationPath.sublocation, !sub.isEmpty {
            for candidate in locations.filter({ $0.name == sub }) {
                let chain = path(of: candidate.id).map(\.name)
                if let city = locationPath.city, !city.isEmpty, !chain.contains(city) { continue }
                if let province = locationPath.province, !province.isEmpty, !chain.contains(province) { continue }
                return candidate.id
            }
        }
        if let city = locationPath.city, !city.isEmpty {
            for candidate in locations.filter({ $0.name == city }) {
                let chain = path(of: candidate.id).map(\.name)
                if let province = locationPath.province, !province.isEmpty, !chain.contains(province) { continue }
                return candidate.id
            }
        }
        if let province = locationPath.province, !province.isEmpty {
            return locations.first(where: { $0.name == province && $0.parentId == nil })?.id
        }
        return nil
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Location].self, from: data) else { return }
        locations = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

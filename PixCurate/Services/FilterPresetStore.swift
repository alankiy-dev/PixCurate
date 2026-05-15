import Foundation
import Observation

@Observable
final class FilterPresetStore {
    static let shared = FilterPresetStore()

    var presets: [FilterPreset] = []

    private let key = "pixcurate.filterPresets"

    init() { load() }

    func add(_ preset: FilterPreset) {
        presets.append(preset)
        persist()
    }

    func update(_ preset: FilterPreset) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx] = preset
        persist()
    }

    func delete(_ preset: FilterPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FilterPreset].self, from: data)
        else { return }
        presets = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

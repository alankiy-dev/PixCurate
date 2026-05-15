import SwiftUI

struct PresetEditSheet: View {
    let preset: FilterPreset
    let currentMinRating: Int
    let currentTagGroups: [[String]]
    let currentLocationIds: [UUID]
    let onSave: (FilterPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LocationStore.self) private var locationStore

    @State private var name: String
    @State private var overwriteConditions = false

    init(preset: FilterPreset,
         currentMinRating: Int,
         currentTagGroups: [[String]],
         currentLocationIds: [UUID],
         onSave: @escaping (FilterPreset) -> Void) {
        self.preset = preset
        self.currentMinRating = currentMinRating
        self.currentTagGroups = currentTagGroups
        self.currentLocationIds = currentLocationIds
        self.onSave = onSave
        _name = State(initialValue: preset.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("プリセットを編集")
                .font(.headline)

            // 名前
            VStack(alignment: .leading, spacing: 6) {
                Text("プリセット名").font(.caption).foregroundStyle(.secondary)
                TextField("名前", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            // 保存済み条件のサマリー
            VStack(alignment: .leading, spacing: 6) {
                Text("保存済みの条件").font(.caption).foregroundStyle(.secondary)
                conditionSummary(
                    rating: preset.minRating,
                    tagGroups: preset.tagGroups,
                    locationIds: preset.locationIds
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // 上書きオプション
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $overwriteConditions) {
                    Text("現在のフィルター条件で上書き")
                        .font(.callout)
                }

                if overwriteConditions {
                    conditionSummary(
                        rating: currentMinRating,
                        tagGroups: currentTagGroups,
                        locationIds: currentLocationIds
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.leading, 4)
                }
            }

            Spacer()

            HStack {
                Button("キャンセル", role: .cancel) { dismiss() }
                Spacer()
                Button("保存") {
                    var updated = preset
                    updated.name = name.trimmingCharacters(in: .whitespaces)
                    if overwriteConditions {
                        updated.minRating = currentMinRating
                        updated.tagGroups = currentTagGroups
                        updated.locationIds = Array(currentLocationIds)
                    }
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360, height: 340)
    }

    @ViewBuilder
    private func conditionSummary(rating: Int, tagGroups: [[String]], locationIds: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text(rating == 0 ? "指定なし" : "★\(rating)以上")
            }
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "tag.fill").foregroundStyle(.blue)
                if tagGroups.isEmpty {
                    Text("指定なし")
                } else {
                    Text(tagGroups.map { $0.joined(separator: " or ") }.joined(separator: " / "))
                        .lineLimit(2)
                }
            }
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(.red)
                if locationIds.isEmpty {
                    Text("指定なし")
                } else {
                    let names = locationIds.compactMap { id in
                        locationStore.path(of: id).last?.name
                    }
                    Text(names.joined(separator: "、")).lineLimit(2)
                }
            }
        }
    }
}

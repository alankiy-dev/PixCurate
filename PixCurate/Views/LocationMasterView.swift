import SwiftUI

// MARK: - Master management sheet

struct LocationMasterView: View {
    @Environment(LocationStore.self) var store
    @Environment(\.dismiss) var dismiss
    @State private var editingLocation: Location?
    @State private var editName = ""
    @State private var newName = ""
    @State private var addingChildOf: UUID? = nil  // nil = root

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("撮影地マスタ管理")
                    .font(.headline)
                Spacer()
                Button("完了") { dismiss() }
                    .keyboardShortcut(.return)
            }
            .padding()

            Divider()

            if store.locations.isEmpty {
                Spacer()
                Text("撮影地がありません。下から追加してください。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(store.children(of: nil)) { l1 in
                        locationRow(l1, level: 0)
                        ForEach(store.children(of: l1.id)) { l2 in
                            locationRow(l2, level: 1)
                            ForEach(store.children(of: l2.id)) { l3 in
                                locationRow(l3, level: 2)
                            }
                        }
                    }
                }
            }

            Divider()

            // Add row
            HStack(spacing: 8) {
                // Parent picker
                Menu {
                    Button("ルート（都道府県）") { addingChildOf = nil }
                    Divider()
                    ForEach(store.locations.filter { $0.parentId == nil }) { l1 in
                        Menu(l1.name) {
                            Button("「\(l1.name)」の直下に追加") { addingChildOf = l1.id }
                            Divider()
                            ForEach(store.children(of: l1.id)) { l2 in
                                Button("「\(l2.name)」の直下に追加") { addingChildOf = l2.id }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(addingParentLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                TextField("新しい地名", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addLocation() }

                Button("追加", action: addLocation)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 500)
        .sheet(item: $editingLocation) { loc in
            editSheet(for: loc)
        }
    }

    private var addingParentLabel: String {
        guard let pid = addingChildOf else { return "ルート" }
        return store.pathString(of: pid)
    }

    @ViewBuilder
    private func locationRow(_ loc: Location, level: Int) -> some View {
        HStack {
            // Indent
            if level > 0 {
                Spacer().frame(width: CGFloat(level) * 18)
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(loc.name)
            Spacer()
            // Quick "add child" button
            if level < 2 {
                Button {
                    addingChildOf = loc.id
                } label: {
                    Image(systemName: "plus").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("この場所の下に追加")
            }
            Button {
                editName = loc.name
                editingLocation = loc
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.borderless)
            Button {
                store.removeLocation(loc)
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func editSheet(for loc: Location) -> some View {
        VStack(spacing: 20) {
            Text("名前を変更").font(.headline)
            Text(store.pathString(of: loc.id))
                .font(.caption).foregroundStyle(.secondary)
            TextField("地名", text: $editName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { saveEdit(loc) }
            HStack(spacing: 12) {
                Button("キャンセル") { editingLocation = nil }
                Button("保存") { saveEdit(loc) }
                    .buttonStyle(.borderedProminent)
                    .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340, height: 180)
    }

    private func addLocation() {
        store.addLocation(name: newName, parentId: addingChildOf)
        newName = ""
    }

    private func saveEdit(_ loc: Location) {
        store.rename(loc, to: editName)
        editingLocation = nil
    }
}

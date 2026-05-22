import SwiftUI

struct MasterSettingsView: View {
    @Environment(TagStore.self) var tagStore
    @Environment(\.dismiss) var dismiss
    @State private var newTagName = ""
    @State private var editingTag: Tag?
    @State private var editName = ""
    @State private var deleteConfirmTag: Tag? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("タグマスタ管理")
                    .font(.headline)
                Spacer()
                Button("完了") { dismiss() }
                    .keyboardShortcut(.return)
            }
            .padding()

            Divider()

            if tagStore.tags.isEmpty {
                VStack {
                    Spacer()
                    Text("タグがありません。下から追加してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(tagStore.tags) { tag in
                        HStack {
                            if tag.parentId != nil {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(tag.name)
                            Spacer()
                            Button {
                                editName = tag.name
                                editingTag = tag
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.borderless)
                            Button {
                                deleteConfirmTag = tag
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Divider()

            // Add new tag
            HStack(spacing: 8) {
                TextField("新しいタグ名", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }
                Button("追加", action: addTag)
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 380, height: 460)
        .alert("タグを削除", isPresented: Binding(
            get: { deleteConfirmTag != nil },
            set: { if !$0 { deleteConfirmTag = nil } }
        )) {
            Button("キャンセル", role: .cancel) { deleteConfirmTag = nil }
            Button("削除", role: .destructive) {
                if let tag = deleteConfirmTag {
                    tagStore.removeTag(tag)
                    deleteConfirmTag = nil
                }
            }
        } message: {
            if let tag = deleteConfirmTag {
                Text("タグ「\(tag.name)」を削除します。この操作は元に戻せません。")
            }
        }
        .sheet(item: $editingTag) { tag in
            editSheet(for: tag)
        }
    }

    private func addTag() {
        tagStore.addTag(name: newTagName)
        newTagName = ""
    }

    @ViewBuilder
    private func editSheet(for tag: Tag) -> some View {
        VStack(spacing: 20) {
            Text("タグを編集")
                .font(.headline)
            TextField("タグ名", text: $editName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { saveEdit(tag) }
            HStack(spacing: 12) {
                Button("キャンセル") { editingTag = nil }
                Button("保存") { saveEdit(tag) }
                    .buttonStyle(.borderedProminent)
                    .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320, height: 160)
    }

    private func saveEdit(_ tag: Tag) {
        tagStore.renameTag(tag, to: editName)
        editingTag = nil
    }
}

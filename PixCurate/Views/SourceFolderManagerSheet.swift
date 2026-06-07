import SwiftUI

// MARK: - SourceFolderManagerSheet

struct SourceFolderManagerSheet: View {
    @Environment(SourceFolderStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var addError: String?
    @State private var showAddError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── ヘッダー ──────────────────────────────────────────────
            HStack {
                Text("コピー元フォルダ")
                    .font(.headline)
                Spacer()
                Button(action: addFolder) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .help("フォルダを追加")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            // ── フォルダ一覧 ──────────────────────────────────────────
            if store.folders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("フォルダが登録されていません")
                        .foregroundStyle(.secondary)
                    Text("右上の ＋ ボタンでフォルダを追加してください")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.folders) { folder in
                        SourceFolderRow(folder: folder)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // ── フッター ──────────────────────────────────────────────
            HStack {
                let total = store.folders.count
                let online = store.folders.filter(\.isOnline).count
                let enabled = store.enabledFolders.count
                if total > 0 {
                    Text("有効 \(enabled) / \(total)・オンライン \(online) / \(total)")
                        .font(.caption)
                        .foregroundStyle(online < total ? Color.orange : Color.secondary)
                }
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 340)
        .alert("フォルダを追加できません", isPresented: $showAddError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let msg = addError { Text(msg) }
        }
    }

    // MARK: - フォルダ追加

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "追加"
        panel.message = "コピー元フォルダを選択してください"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.add(url: url, isRecursive: true)
        } catch {
            addError = error.localizedDescription
            showAddError = true
        }
    }
}

// MARK: - SourceFolderRow

private struct SourceFolderRow: View {
    @Environment(SourceFolderStore.self) private var store
    let folder: SourceFolder

    var body: some View {
        HStack(spacing: 10) {
            // 有効（検索対象＋タブ表示）チェックボックス
            Button {
                store.setEnabled(id: folder.id, isEnabled: !folder.isEnabled)
            } label: {
                Image(systemName: folder.isEnabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(folder.isEnabled ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(folder.isEnabled ? "有効（検索対象・タブ表示）。クリックで除外" : "除外中。クリックで検索対象・タブ表示に含める")

            // オンライン/オフライン インジケーター
            Circle()
                .fill(folder.isOnline ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 9, height: 9)

            // パス表示
            VStack(alignment: .leading, spacing: 2) {
                let folderName = URL(fileURLWithPath: folder.displayPath).lastPathComponent
                HStack(spacing: 4) {
                    Text(folderName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if !folder.isOnline {
                        Text("オフライン")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
                Text(folder.displayPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .opacity(folder.isEnabled ? 1.0 : 0.4)

            Spacer()

            // サブフォルダ トグル
            Button {
                store.setRecursive(id: folder.id, isRecursive: !folder.isRecursive)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: folder.isRecursive
                          ? "checkmark.square.fill"
                          : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(folder.isRecursive ? Color.accentColor : Color.secondary)
                    Text("サブフォルダを含む")
                        .font(.system(size: 11))
                        .foregroundStyle(folder.isRecursive ? Color.primary : Color.secondary)
                }
            }
            .buttonStyle(.borderless)
            .help(folder.isRecursive ? "サブフォルダを含む（クリックでオフ）" : "このフォルダのみ（クリックでオン）")

            // 削除ボタン（マイナス）
            Button {
                store.remove(id: folder.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.red.opacity(0.75))
            }
            .buttonStyle(.borderless)
            .help("このフォルダを削除")
        }
        .padding(.vertical, 5)
    }
}

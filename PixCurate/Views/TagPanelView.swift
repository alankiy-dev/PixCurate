import SwiftUI

// MARK: - TagPanelView

struct TagPanelView: View {
    let selectedFiles: [PhotoFile]
    let vm: FileListViewModel
    @Environment(TagStore.self) var tagStore
    @State private var showMaster = false
    @State private var overrides: [String: Bool] = [:]
    @State private var isWriting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("タグ")
                    .font(.headline)
                if !selectedFiles.isEmpty {
                    Text("(\(selectedFiles.count)件)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { showMaster = true } label: {
                    Image(systemName: "tag.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.borderless)
                .help("タグマスタ管理")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if tagStore.tags.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("タグがありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("タグを追加") { showMaster = true }
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(rootTags) { tag in
                            TagCheckRow(
                                tag: tag,
                                selectedFiles: selectedFiles,
                                override: overrides[tag.name],
                                onToggle: { toggle(tag.name) }
                            )
                            ForEach(childTags(of: tag)) { child in
                                TagCheckRow(
                                    tag: child,
                                    selectedFiles: selectedFiles,
                                    override: overrides[child.name],
                                    onToggle: { toggle(child.name) }
                                )
                                .padding(.leading, 14)
                            }
                        }
                    }
                    .padding(8)
                }

                Divider()

                // Write button
                Group {
                    if isWriting {
                        HStack {
                            ProgressView().scaleEffect(0.6)
                            Text("書き込み中...").font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Button { applyTags() } label: {
                            Label("タグを書き込む", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(overrides.isEmpty)
                        .help(overrides.isEmpty ? "タグを選択してください" : "\(overrides.count)件の変更を書き込む")
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 200)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: selectedFiles.map { $0.id }) { _, _ in overrides = [:] }
        .sheet(isPresented: $showMaster) {
            MasterSettingsView().environment(tagStore)
        }
    }

    private var rootTags: [Tag] { tagStore.tags.filter { $0.parentId == nil } }
    private func childTags(of tag: Tag) -> [Tag] { tagStore.tags.filter { $0.parentId == tag.id } }

    private func toggle(_ tagName: String) {
        let isEffectivelyOn: Bool
        if let ov = overrides[tagName] {
            isEffectivelyOn = ov
        } else {
            let count = selectedFiles.filter { $0.tags.contains(tagName) }.count
            isEffectivelyOn = count == selectedFiles.count && !selectedFiles.isEmpty
        }
        overrides[tagName] = !isEffectivelyOn
    }

    private func applyTags() {
        let ov = overrides
        let files = selectedFiles
        isWriting = true

        Task.detached(priority: .userInitiated) {
            var updates: [(URL, [String])] = []
            for file in files {
                var newTags = file.tags
                for (tagName, shouldHave) in ov {
                    if shouldHave, !newTags.contains(tagName) {
                        newTags.append(tagName)
                    } else if !shouldHave {
                        newTags.removeAll { $0 == tagName }
                    }
                }
                _ = XMPTagService.writeTags(to: file.xmpURL, tags: newTags)
                updates.append((file.rawURL, newTags))
            }
            let finalUpdates = updates
            await MainActor.run {
                for (url, tags) in finalUpdates {
                    vm.updateTags(for: url, tags: tags)
                }
                overrides = [:]
                isWriting = false
            }
        }
    }
}

// MARK: - TagCheckRow

struct TagCheckRow: View {
    let tag: Tag
    let selectedFiles: [PhotoFile]
    let override: Bool?
    let onToggle: () -> Void

    private enum CheckState { case all, some, none }

    private var effectiveState: CheckState {
        if let ov = override { return ov ? .all : .none }
        let count = selectedFiles.filter { $0.tags.contains(tag.name) }.count
        if count == 0 { return .none }
        return count == selectedFiles.count ? .all : .some
    }

    var body: some View {
        Button { onToggle() } label: {
            HStack(spacing: 6) {
                stateIcon
                    .frame(width: 16)
                Text(tag.name)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                if override != nil {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(effectiveState != .none ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch effectiveState {
        case .all:
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(Color.accentColor)
        case .some:
            Image(systemName: "minus.square.fill")
                .foregroundStyle(Color.accentColor.opacity(0.6))
        case .none:
            Image(systemName: "square")
                .foregroundStyle(Color.secondary)
        }
    }
}

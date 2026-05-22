import SwiftUI

// MARK: - Model

struct TagFilterGroup: Identifiable {
    let id = UUID()
    var tagNames: Set<String> = []
}

// MARK: - Builder (used inside List/Section in the sidebar)

struct TagFilterBuilderView: View {
    @Binding var filterGroups: [TagFilterGroup]
    let allTags: [Tag]
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if filterGroups.isEmpty {
                HStack {
                    Text("絞り込みなし")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { addGroup() } label: {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help("タグ絞り込みを追加")
                }
            } else {
                ForEach(0..<filterGroups.count, id: \.self) { i in
                    if i > 0 {
                        // AND connector
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(height: 0.5)
                            Text("AND")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.orange)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(height: 0.5)
                        }
                    }
                    FilterGroupRowView(
                        tagNames: Binding(
                            get: { i < filterGroups.count ? filterGroups[i].tagNames : [] },
                            set: { if i < filterGroups.count { filterGroups[i].tagNames = $0; onChange() } }
                        ),
                        allTags: allTags,
                        onRemove: {
                            if i < filterGroups.count { filterGroups.remove(at: i); onChange() }
                        }
                    )
                }

                HStack {
                    Button { addGroup() } label: {
                        Label("AND条件を追加", systemImage: "plus")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("クリア") { filterGroups = []; onChange() }
                        .font(.callout)
                        .foregroundStyle(.red)
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func addGroup() {
        filterGroups.append(TagFilterGroup())
    }
}

// MARK: - Group Row

struct FilterGroupRowView: View {
    @Binding var tagNames: Set<String>
    let allTags: [Tag]
    let onRemove: () -> Void
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 4) {
            Button { showPicker.toggle() } label: {
                groupLabel
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(showPicker ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker, arrowEdge: .trailing) {
                TagPickerPopoverView(selectedNames: $tagNames, allTags: allTags)
            }

            Button { onRemove() } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var groupLabel: some View {
        if tagNames.isEmpty {
            Text("タグを選択…")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            // Show chips with OR separator
            let sorted = tagNames.sorted()
            HStack(spacing: 3) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { idx, name in
                    if idx > 0 {
                        Text("OR")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Tag Picker Popover

struct TagPickerPopoverView: View {
    @Binding var selectedNames: Set<String>
    let allTags: [Tag]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("OR条件のタグを選択")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("どれか1つ以上に一致する写真を表示")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(allTags) { tag in
                        HStack(spacing: 8) {
                            Image(systemName: selectedNames.contains(tag.name)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedNames.contains(tag.name)
                                                 ? Color.accentColor : .secondary)
                                .font(.system(size: 15))
                            Text(tag.name)
                                .font(.callout)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedNames.contains(tag.name) {
                                selectedNames.remove(tag.name)
                            } else {
                                selectedNames.insert(tag.name)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selectedNames.contains(tag.name)
                                    ? Color.accentColor.opacity(0.07) : Color.clear)
                    }
                }
            }
        }
        .frame(width: 220, height: min(CGFloat(allTags.count) * 38 + 64, 320))
    }
}

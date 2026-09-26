import SwiftUI

// Tristate tree checkbox filter.
// selectedIds stores ONLY leaf-node IDs.
// Parent tristate is derived from the ratio of selected leaves in its subtree.
// This means: if all leaves under 由布市 are selected → 由布市 shows ◼️,
// even though 由布市 itself is not in selectedIds.
//
// 撮影地が増えても扱いやすいよう、検索欄・選択チップ・高さ制限スクロールを備える。

struct LocationFilterView: View {
    @Binding var selectedIds: Set<UUID>
    let store: LocationStore
    let onChange: () -> Void

    @State private var searchText = ""

    private var trimmed: String { searchText.trimmingCharacters(in: .whitespaces) }

    /// 検索時に表示するノード集合（一致ノード＋その先祖＋その子孫）。nil のとき全表示。
    private var visibleIds: Set<UUID>? {
        guard !trimmed.isEmpty else { return nil }
        var result = Set<UUID>()
        for loc in store.locations where loc.name.localizedCaseInsensitiveContains(trimmed) {
            result.formUnion(store.selfAndAncestors(of: loc.id))
            result.formUnion(store.descendants(of: loc.id))
        }
        return result
    }

    /// 選択中の撮影地（チップ表示用）。locations の並び順で安定表示。
    private var selectedChips: [Location] {
        store.locations.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.locations.isEmpty {
                Text("撮影地なし")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                // 検索欄
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("地名で絞り込み…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !trimmed.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.10)))

                // 選択チップ（折返し・✕で個別解除）
                if !selectedChips.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(selectedChips, id: \.id) { loc in
                            Button {
                                selectedIds.remove(loc.id)
                                onChange()
                            } label: {
                                HStack(spacing: 3) {
                                    Text(loc.name).font(.caption)
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .foregroundStyle(Color.accentColor)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // ツリー（高さ制限スクロール）
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.children(of: nil)) { loc in
                            LocationFilterNodeView(
                                location: loc,
                                store: store,
                                selectedIds: $selectedIds,
                                onChange: onChange,
                                visibleIds: visibleIds,
                                forceExpand: !trimmed.isEmpty
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)

                if !selectedIds.isEmpty {
                    Button("すべてクリア") { selectedIds = []; onChange() }
                        .font(.caption)
                        .foregroundStyle(.red)
                        .buttonStyle(.borderless)
                        .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - Node

struct LocationFilterNodeView: View {
    let location: Location
    let store: LocationStore
    @Binding var selectedIds: Set<UUID>
    let onChange: () -> Void
    /// nil のとき全表示。非nilのとき、この集合に含まれるノードだけ表示（検索絞り込み）。
    var visibleIds: Set<UUID>? = nil
    /// 検索中は常に展開して一致ノードまで見えるようにする。
    var forceExpand: Bool = false

    @State private var isExpanded = true

    private var children: [Location] { store.children(of: location.id) }
    private var isLeafNode: Bool { children.isEmpty }
    private var isVisible: Bool { visibleIds?.contains(location.id) ?? true }
    private var expanded: Bool { forceExpand ? true : isExpanded }

    /// All leaf IDs in this subtree (self if leaf; otherwise only leaf descendants)
    private var leaves: Set<UUID> {
        if isLeafNode { return [location.id] }
        return store.descendants(of: location.id)
            .filter { store.children(of: $0).isEmpty }
    }

    private enum TriState { case all, some, none }

    private var tristate: TriState {
        let lv = leaves
        let count = lv.filter { selectedIds.contains($0) }.count
        if count == 0        { return .none }
        if count == lv.count { return .all  }
        return .some
    }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    // Checkbox — controls leaf selection
                    Button { toggle() } label: {
                        checkboxIcon
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)

                    if isLeafNode {
                        Text(location.name)
                            .font(.callout)
                            .foregroundStyle(tristate == .none ? .primary : Color.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { toggle() }
                    } else {
                        // Disclosure toggle (separate from checkbox)
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(location.name)
                                    .font(.callout)
                                    .foregroundStyle(tristate == .none ? .primary : Color.accentColor)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(forceExpand)
                    }
                }
                .padding(.vertical, 2)

                if !isLeafNode && expanded {
                    ForEach(children) { child in
                        LocationFilterNodeView(
                            location: child,
                            store: store,
                            selectedIds: $selectedIds,
                            onChange: onChange,
                            visibleIds: visibleIds,
                            forceExpand: forceExpand
                        )
                        .padding(.leading, 18)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var checkboxIcon: some View {
        switch tristate {
        case .all:
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 15))
        case .some:
            Image(systemName: "minus.square.fill")
                .foregroundStyle(Color.accentColor.opacity(0.7))
                .font(.system(size: 15))
        case .none:
            Image(systemName: "square")
                .foregroundStyle(Color.secondary)
                .font(.system(size: 15))
        }
    }

    private func toggle() {
        let lv = leaves
        if tristate == .all {
            selectedIds.subtract(lv)   // deselect all leaves
        } else {
            selectedIds.formUnion(lv)  // select all leaves
        }
        onChange()
    }
}

// MARK: - FlowLayout（チップの折返し配置）

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        let width = maxW.isFinite ? maxW : x
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                    proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

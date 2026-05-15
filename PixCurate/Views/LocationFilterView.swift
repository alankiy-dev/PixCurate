import SwiftUI

// Tristate tree checkbox filter.
// selectedIds stores ONLY leaf-node IDs.
// Parent tristate is derived from the ratio of selected leaves in its subtree.
// This means: if all leaves under 由布市 are selected → 由布市 shows ◼️,
// even though 由布市 itself is not in selectedIds.

struct LocationFilterView: View {
    @Binding var selectedIds: Set<UUID>
    let store: LocationStore
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.locations.isEmpty {
                Text("撮影地なし")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(store.children(of: nil)) { loc in
                    LocationFilterNodeView(
                        location: loc,
                        store: store,
                        selectedIds: $selectedIds,
                        onChange: onChange
                    )
                }
                if !selectedIds.isEmpty {
                    Button("クリア") { selectedIds = []; onChange() }
                        .font(.caption)
                        .foregroundStyle(.red)
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
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
    @State private var isExpanded = true

    private var children: [Location] { store.children(of: location.id) }
    private var isLeafNode: Bool { children.isEmpty }

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
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(location.name)
                                .font(.callout)
                                .foregroundStyle(tristate == .none ? .primary : Color.accentColor)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)

            if !isLeafNode && isExpanded {
                ForEach(children) { child in
                    LocationFilterNodeView(
                        location: child,
                        store: store,
                        selectedIds: $selectedIds,
                        onChange: onChange
                    )
                    .padding(.leading, 18)
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

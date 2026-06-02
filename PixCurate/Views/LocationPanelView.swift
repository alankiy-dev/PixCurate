import SwiftUI

// MARK: - Location assignment panel

struct LocationPanelView: View {
    let selectedFiles: [PhotoFile]
    let vm: FileListViewModel
    @Environment(LocationStore.self) var store
    @State private var pendingId: UUID? = nil
    @State private var hasPending = false
    @State private var isWriting = false
    @State private var showMaster = false
    @State private var searchText = ""

    // What location is currently set on the selection
    private enum CurrentLocation: Equatable {
        case none, single(UUID), mixed
    }
    private var current: CurrentLocation {
        guard !selectedFiles.isEmpty else { return .none }
        let ids = Set(selectedFiles.map { $0.locationId })
        if ids.count == 1, let id = ids.first { return id == nil ? .none : .single(id!) }
        return .mixed
    }
    private var displayedId: UUID? {
        hasPending ? pendingId : (current == .mixed ? nil : { if case .single(let id) = current { return id }; return nil }())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("撮影地")
                    .font(.headline)
                if !selectedFiles.isEmpty {
                    Text("(\(selectedFiles.count)件)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showMaster = true } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 15))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Current location badge
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.secondary).font(.caption)
                Group {
                    switch current {
                    case .none:
                        Text("未設定").foregroundStyle(.secondary)
                    case .single(let id):
                        Text(store.pathString(of: id))
                    case .mixed:
                        Text("複数の撮影地").foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
                .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.06))

            Divider()

            if store.locations.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("撮影地が登録されていません")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("マスタ管理") { showMaster = true }
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // 検索フィールド
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("撮影地を検索", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))

                Divider()

                // Location tree or search results
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if searchText.isEmpty {
                            // 通常ツリー表示
                            ForEach(store.children(of: nil)) { loc in
                                LocationNodeRow(
                                    location: loc,
                                    store: store,
                                    selectedId: displayedId,
                                    isPending: hasPending,
                                    onSelect: { id in
                                        pendingId = (pendingId == id && hasPending) ? nil : id
                                        hasPending = pendingId != nil
                                    }
                                )
                            }
                        } else {
                            // 検索結果をフラットに表示
                            let results = store.locations.filter {
                                $0.name.localizedCaseInsensitiveContains(searchText)
                            }
                            if results.isEmpty {
                                Text("一致する撮影地がありません")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                            } else {
                                ForEach(results) { loc in
                                    LocationSearchRow(
                                        location: loc,
                                        store: store,
                                        selectedId: displayedId,
                                        isPending: hasPending,
                                        onSelect: { id in
                                            pendingId = (pendingId == id && hasPending) ? nil : id
                                            hasPending = pendingId != nil
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
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
                        Button { applyLocation() } label: {
                            Label("撮影地を書き込む", systemImage: "mappin.and.ellipse")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasPending)
                    }
                }
                .padding(10)
            }
        }
        .onChange(of: selectedFiles.map { $0.id }) { _, _ in
            hasPending = false
            pendingId = nil
        }
        .sheet(isPresented: $showMaster) {
            LocationMasterView().environment(store)
        }
    }

    private func applyLocation() {
        let locId = pendingId
        let locPath = locId.flatMap { store.buildLocationPath(for: $0) }
        let files = selectedFiles
        isWriting = true

        Task.detached(priority: .userInitiated) {
            var updates: [(URL, UUID?, LocationPath?)] = []
            for file in files {
                if let p = locPath {
                    _ = XMPLocationService.writeLocation(to: file.xmpURL, path: p)
                }
                updates.append((file.rawURL, locId, locPath))
            }
            let final = updates
            await MainActor.run {
                for (url, lid, lpath) in final {
                    vm.updateLocation(for: url, locationId: lid, locationPath: lpath)
                }
                hasPending = false
                isWriting = false
            }
        }
    }
}

// MARK: - Recursive tree row

struct LocationNodeRow: View {
    let location: Location
    let store: LocationStore
    let selectedId: UUID?
    let isPending: Bool
    let onSelect: (UUID) -> Void
    @State private var isExpanded = true

    private var children: [Location] { store.children(of: location.id) }
    private var isSelected: Bool { selectedId == location.id }

    var body: some View {
        if children.isEmpty {
            // Leaf — radio button
            leafRow
        } else {
            // Branch — custom disclosure (DisclosureGroupはデフォルト余白が大きいため自前実装)
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    branchLabel
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(children) { child in
                            LocationNodeRow(
                                location: child,
                                store: store,
                                selectedId: selectedId,
                                isPending: isPending,
                                onSelect: onSelect
                            )
                            .padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var leafRow: some View {
        HStack(spacing: 6) {
            Image(systemName: isSelected
                  ? (isPending ? "largecircle.fill.circle" : "record.circle.fill")
                  : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.system(size: 14))
            Text(location.name)
                .font(.callout)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(location.id) }
        .padding(.vertical, 0)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var branchLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .foregroundStyle(.secondary)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 10)
            Image(systemName: "mappin.circle")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            Text(location.name)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
    }
}

// MARK: - Search result row（パス付きフラット表示）

struct LocationSearchRow: View {
    let location: Location
    let store: LocationStore
    let selectedId: UUID?
    let isPending: Bool
    let onSelect: (UUID) -> Void

    private var isSelected: Bool { selectedId == location.id }
    private var pathLabel: String { store.pathString(of: location.id) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isSelected
                  ? (isPending ? "largecircle.fill.circle" : "record.circle.fill")
                  : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text(location.name)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                Text(pathLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(location.id) }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

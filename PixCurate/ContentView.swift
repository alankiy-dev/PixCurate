import SwiftUI
import Observation

// MARK: - UserDefaults keys

private enum Keys {
    static let srcPath       = "pixcurate.srcPath"
    static let dstPath       = "pixcurate.dstPath"
    static let minRating     = "pixcurate.minRating"
    static let keepStructure = "pixcurate.keepStructure"
}

// MARK: - ViewModel

@MainActor
@Observable
class FileListViewModel {
    var allFiles: [PhotoFile] = []
    var filteredFiles: [PhotoFile] = []
    var isLoading = false
    var logLines: [String] = []
    var isRunning = false
    var exiftoolMissing = false

    func load(from url: URL, minRating: Int) {
        isLoading = true
        allFiles = []
        filteredFiles = []
        exiftoolMissing = false

        Task.detached {
            let result = FileListViewModel.scan(url: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                exiftoolMissing = result.exiftoolMissing
                var files = result.files
                let locStore = LocationStore.shared
                for i in files.indices {
                    if let path = files[i].locationPath {
                        files[i].locationId = locStore.match(path: path)
                    }
                }
                allFiles = files
                applyFilter(minRating: minRating)
                isLoading = false
            }
        }
    }

    private nonisolated static func scan(url: URL) -> (files: [PhotoFile], exiftoolMissing: Bool) {
        let rawExtensions: Set<String> = ["raf", "arw", "cr3"]
        let fm = FileManager.default
        var scanned: [PhotoFile] = []

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], false)
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard rawExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            var file = PhotoFile(rawURL: fileURL)
            let xmpURL = file.xmpURL
            if fm.fileExists(atPath: xmpURL.path) {
                // XMPを直接テキスト解析（exiftool不要・サンドボックス対応）
                file.rating = XMPService.readRating(xmpURL: xmpURL)
                file.tags = XMPTagService.readTags(xmpURL: xmpURL)
                file.locationPath = XMPLocationService.readLocation(xmpURL: xmpURL)
            }
            // Prefer EXIF shooting date; fall back to file modification date
            file.shotDate = EXIFService.readShotDate(url: fileURL)
                ?? (try? fm.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
            scanned.append(file)
        }

        scanned.sort { $0.filename < $1.filename }
        return (scanned, false)
    }

    var locationFilter: Set<UUID> = []

    func updateRating(for rawURL: URL, rating: Int?) {
        if let idx = allFiles.firstIndex(where: { $0.rawURL == rawURL }) {
            allFiles[idx].rating = rating
        }
        if let idx = filteredFiles.firstIndex(where: { $0.rawURL == rawURL }) {
            filteredFiles[idx].rating = rating
        }
    }

    func updateTags(for rawURL: URL, tags: [String]) {
        if let idx = allFiles.firstIndex(where: { $0.rawURL == rawURL }) {
            allFiles[idx].tags = tags
        }
        if let idx = filteredFiles.firstIndex(where: { $0.rawURL == rawURL }) {
            filteredFiles[idx].tags = tags
        }
    }

    func updateLocation(for rawURL: URL, locationId: UUID?, locationPath: LocationPath?) {
        if let idx = allFiles.firstIndex(where: { $0.rawURL == rawURL }) {
            allFiles[idx].locationId = locationId
            allFiles[idx].locationPath = locationPath
        }
        if let idx = filteredFiles.firstIndex(where: { $0.rawURL == rawURL }) {
            filteredFiles[idx].locationId = locationId
            filteredFiles[idx].locationPath = locationPath
        }
    }

    // Each inner array = one OR-group; outer array connected by AND
    var filterGroups: [[String]] = []

    func applyFilter(minRating: Int) {
        filteredFiles = allFiles.filter { file in
            let ratingOK = minRating == 0 || (file.rating ?? 0) >= minRating
            let tagOK = filterGroups.isEmpty || filterGroups.allSatisfy { group in
                group.isEmpty || group.contains { file.tags.contains($0) }
            }
            let locationOK = locationFilter.isEmpty || (file.locationId.map { locationFilter.contains($0) } ?? false)
            return ratingOK && tagOK && locationOK
        }
    }

    func runCopy(to dst: URL, keepStructure: Bool, baseURL: URL, dryRun: Bool) {
        logLines = []
        isRunning = true
        let files = filteredFiles

        Task.detached {
            let service = CopyService()
            // ログを一時バッファに収集してMainActorへ一括送信
            nonisolated(unsafe) var buffer: [String] = []
            let result = service.copy(
                files: files,
                to: dst,
                keepStructure: keepStructure,
                baseURL: baseURL,
                dryRun: dryRun,
                log: { line in buffer.append(line) }
            )
            buffer.append("══════════════════════════════════")
            buffer.append(dryRun
                ? "✅ プレビュー対象  : \(result.copied) ファイル"
                : "✅ コピー完了      : \(result.copied) ファイル")
            buffer.append("⏭  スキップ（同一）: \(result.skipped) ファイル")
            if result.errors > 0 { buffer.append("❌ エラー          : \(result.errors) ファイル") }
            buffer.append("══════════════════════════════════")
            let finalBuffer = buffer
            await MainActor.run { [weak self] in
                guard let self else { return }
                logLines.append(contentsOf: finalBuffer)
                isRunning = false
            }
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var vm = FileListViewModel()
    @Environment(TagStore.self) private var tagStore

    @State private var srcURL: URL? = BookmarkStore.restore(Keys.srcPath)
    @State private var dstURL: URL? = BookmarkStore.restore(Keys.dstPath)
    @State private var minRating: Int = UserDefaults.standard.object(forKey: Keys.minRating) as? Int ?? 1
    @State private var keepStructure: Bool = UserDefaults.standard.bool(forKey: Keys.keepStructure)
    @State private var selection: Set<UUID> = []
    @State private var filterGroups: [TagFilterGroup] = []
    @State private var selectedLocationIds: Set<UUID> = []
    @State private var showDisplaySettings = false
    @State private var showCopyConfirm = false
    @State private var ratingFilterExpanded = true
    @State private var tagFilterExpanded = true
    @State private var locationFilterExpanded = true
    @State private var presetExpanded = true
    @State private var activePresetId: UUID?
    @State private var showSavePreset = false
    @State private var presetName = ""
    @State private var editingPreset: FilterPreset?
    @Environment(LocationStore.self) private var locationStore
    @Environment(DisplaySettings.self) private var displaySettings
    @Environment(FilterPresetStore.self) private var presetStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detailView
        }
        .frame(minWidth: 740, minHeight: 520)
        .onChange(of: srcURL, initial: true) { _, newVal in
            BookmarkStore.save(url: newVal, key: Keys.srcPath)
            if let url = newVal {
                vm.load(from: url, minRating: minRating)
            }
        }
        .onChange(of: dstURL) { _, newVal in
            BookmarkStore.save(url: newVal, key: Keys.dstPath)
        }
        .onChange(of: minRating) { _, newVal in
            UserDefaults.standard.set(newVal, forKey: Keys.minRating)
            vm.applyFilter(minRating: newVal)
            clearActivePreset()
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    FolderPickerRow(label: "コピー元", url: $srcURL)
                    FolderPickerRow(label: "コピー先", url: $dstURL)
                } header: {
                    sectionHeader("フォルダ")
                }

                Section {
                    // 評価
                    DisclosureGroup(isExpanded: $ratingFilterExpanded) {
                        StarPickerView(selection: $minRating)
                            .padding(.vertical, 4)
                    } label: {
                        filterLabel("評価", icon: "star.fill", color: .yellow)
                    }

                    // タグ
                    if !tagStore.tags.isEmpty {
                        DisclosureGroup(isExpanded: $tagFilterExpanded) {
                            TagFilterBuilderView(
                                filterGroups: $filterGroups,
                                allTags: tagStore.tags,
                                onChange: { applyTagFilter() }
                            )
                        } label: {
                            filterLabel("タグ", icon: "tag.fill", color: .blue)
                        }
                    }

                    // 撮影地
                    if !locationStore.locations.isEmpty {
                        DisclosureGroup(isExpanded: $locationFilterExpanded) {
                            LocationFilterView(
                                selectedIds: $selectedLocationIds,
                                store: locationStore,
                                onChange: { applyLocationFilter() }
                            )
                        } label: {
                            filterLabel("撮影地", icon: "mappin.and.ellipse", color: .red)
                        }
                    }
                } header: {
                    sectionHeader("フィルター")
                }

                Section {
                    DisclosureGroup(isExpanded: $presetExpanded) {
                        if presetStore.presets.isEmpty {
                            Text("保存済みのプリセットはありません")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(presetStore.presets) { preset in
                                let isActive = activePresetId == preset.id
                                HStack(spacing: 6) {
                                    Button {
                                        applyPreset(preset)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: isActive
                                                  ? "checkmark.circle.fill"
                                                  : "line.3.horizontal.decrease.circle")
                                                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                                                .font(.caption)
                                            Text(preset.name)
                                                .font(.callout)
                                                .fontWeight(isActive ? .semibold : .regular)
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        editingPreset = preset
                                    } label: {
                                        Image(systemName: "square.and.pencil")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    Button {
                                        presetStore.delete(preset)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                                .background(
                                    isActive
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        Button {
                            presetName = ""
                            showSavePreset = true
                        } label: {
                            Label("現在の条件を保存...", systemImage: "plus.circle")
                                .font(.callout)
                        }
                        .alert("プリセットを保存", isPresented: $showSavePreset) {
                            TextField("プリセット名", text: $presetName)
                            Button("キャンセル", role: .cancel) {}
                            Button("保存") { savePreset() }
                                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                        } message: {
                            Text("現在の評価・タグ・撮影地フィルターを保存します")
                        }
                    } label: {
                        sectionHeader("プリセット")
                    }
                }

                Section {
                    Toggle("フォルダ構造を維持", isOn: $keepStructure)
                        .onChange(of: keepStructure) { _, v in
                            UserDefaults.standard.set(v, forKey: Keys.keepStructure)
                        }
                    copySection
                } header: {
                    sectionHeader("コピー")
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("終了", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .sheet(item: $editingPreset) { preset in
            PresetEditSheet(
                preset: preset,
                currentMinRating: minRating,
                currentTagGroups: vm.filterGroups,
                currentLocationIds: Array(selectedLocationIds),
                onSave: { presetStore.update($0) }
            )
            .environment(locationStore)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .textCase(nil)
    }

    private func filterLabel(_ title: String, icon: String, color: Color) -> some View {
        Label {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }

    private func applyTagFilter(clearPreset: Bool = true) {
        vm.filterGroups = filterGroups.map { Array($0.tagNames) }
        vm.applyFilter(minRating: minRating)
        if clearPreset { activePresetId = nil }
    }

    private func applyLocationFilter(clearPreset: Bool = true) {
        vm.locationFilter = selectedLocationIds
        vm.applyFilter(minRating: minRating)
        if clearPreset { activePresetId = nil }
    }

    private func clearActivePreset() {
        activePresetId = nil
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let preset = FilterPreset(
            name: name,
            minRating: minRating,
            tagGroups: vm.filterGroups,
            locationIds: Array(selectedLocationIds)
        )
        presetStore.add(preset)
    }

    private func applyPreset(_ preset: FilterPreset) {
        minRating = preset.minRating
        filterGroups = preset.tagGroups.map { tags in
            var g = TagFilterGroup()
            g.tagNames = Set(tags)
            return g
        }
        selectedLocationIds = Set(preset.locationIds)
        activePresetId = preset.id
        applyTagFilter(clearPreset: false)
        applyLocationFilter(clearPreset: false)
    }

    @ViewBuilder
    private var copySection: some View {
        if srcURL != nil, let dst = dstURL, let src = srcURL {
            Button {
                vm.runCopy(to: dst, keepStructure: keepStructure, baseURL: src, dryRun: true)
            } label: {
                Label("プレビュー（\(vm.filteredFiles.count)件）", systemImage: "eye")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(vm.isRunning || vm.filteredFiles.isEmpty)

            Button {
                showCopyConfirm = true
            } label: {
                Label("コピー実行", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isRunning || vm.filteredFiles.isEmpty)
            .alert("コピーの確認", isPresented: $showCopyConfirm) {
                Button("キャンセル", role: .cancel) {}
                Button("コピー実行") {
                    vm.runCopy(to: dst, keepStructure: keepStructure, baseURL: src, dryRun: false)
                }
            } message: {
                Text("""
                現在表示されている画像がコピー対象となります。

                コピー元: \(src.path)
                コピー先: \(dst.path)
                対象: \(vm.filteredFiles.count) 件
                """)
            }

            if vm.isRunning {
                HStack {
                    ProgressView().scaleEffect(0.65)
                    Text("処理中...").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("コピー元・先を選択してください")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Detail

    private var selectedFilesList: [PhotoFile] {
        vm.filteredFiles.filter { selection.contains($0.id) }
    }

    private var detailView: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // ステータスバー
                HStack(spacing: 6) {
                    if vm.isLoading {
                        ProgressView().scaleEffect(0.65)
                        Text("読み込み中...").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(vm.filteredFiles.count) / \(vm.allFiles.count) ファイル")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !selection.isEmpty {
                            Text("・\(selection.count)件選択中")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Spacer()
                    if !vm.filteredFiles.isEmpty {
                        Button {
                            selection = Set(vm.filteredFiles.map(\.id))
                        } label: {
                            Image(systemName: "square.stack.fill")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .help("全選択")

                        Button {
                            selection.removeAll()
                        } label: {
                            Image(systemName: "square.stack")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .disabled(selection.isEmpty)
                        .help("全解除")

                        Divider().frame(height: 14)
                    }
                    if !selection.isEmpty {
                        Button {
                            if let file = vm.filteredFiles.first(where: { selection.contains($0.id) }) {
                                openWindow(id: "photo-viewer", value: file.rawURL)
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .help("拡大表示")
                    }
                    Button {
                        showDisplaySettings.toggle()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("表示設定")
                    .popover(isPresented: $showDisplaySettings, arrowEdge: .top) {
                        DisplaySettingsView()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)

                Divider()

                FileListView(files: vm.filteredFiles, totalCount: vm.allFiles.count, selection: $selection)

                if !vm.logLines.isEmpty || vm.isRunning {
                    Divider()
                    VStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Text("ログ")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !vm.isRunning {
                                Button {
                                    vm.logLines = []
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.borderless)
                                .help("ログを閉じる")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.bar)

                        logView
                    }
                    .frame(height: 160)
                }
            }

            if !selection.isEmpty {
                Divider()
                InfoPanelView(selectedFiles: selectedFilesList, vm: vm)
            }
        }
    }

    // MARK: - Log

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(vm.logLines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(logColor(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: vm.logLines.count) { _, _ in
                if let last = vm.logLines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func logColor(_ line: String) -> Color {
        if line.hasPrefix("❌") { return .red }
        if line.hasPrefix("✅") { return .green }
        if line.hasPrefix("★") { return .primary }
        if line.hasPrefix("  [プレビュー") { return .blue }
        return .secondary
    }
}

// MARK: - FolderPickerRow

struct FolderPickerRow: View {
    let label: String
    @Binding var url: URL?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                if let url {
                    Text(url.path)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .font(.caption)
                        .foregroundStyle(.primary)
                } else {
                    Text("未選択")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("選択") { pick() }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "\(label)を選択"
        if panel.runModal() == .OK { url = panel.url }
    }
}

// MARK: - StarPickerView

struct StarPickerView: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            Button("全") { selection = 0 }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(selection == 0 ? .primary : .secondary)

            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= selection ? "star.fill" : "star")
                    .foregroundStyle(star <= selection ? Color.yellow : Color.secondary.opacity(0.4))
                    .font(.system(size: 14))
                    .onTapGesture { selection = star }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}

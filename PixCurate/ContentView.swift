import SwiftUI
import Observation

// MARK: - WindowAccessor
// NSViewRepresentable を使いウィンドウが確定したタイミングでコールバックを呼ぶ

private struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Helpers

private extension Date {
    var csvSuffix: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: self)
    }
}


// MARK: - UserDefaults keys

private enum Keys {
    static let srcPath                  = "pixcurate.srcPath"
    static let dstPath                  = "pixcurate.dstPath"
    static let minRating                = "pixcurate.minRating"
    static let keepStructure            = "pixcurate.keepStructure"
    static let dateFilterMode           = "pixcurate.dateFilterMode"
    static let shotDateFrom             = "pixcurate.shotDateFrom"
    static let shotDateTo               = "pixcurate.shotDateTo"
    static let shotDateFilterExpanded   = "pixcurate.filter.shotdate.expanded"
    static let useXmpSince              = "pixcurate.useXmpSince"
    static let xmpSinceDate             = "pixcurate.xmpSinceDate"
    static let ratingFilterExpanded     = "pixcurate.filter.rating.expanded"
    static let tagFilterExpanded        = "pixcurate.filter.tag.expanded"
    static let locationFilterExpanded   = "pixcurate.filter.location.expanded"
    static let xmpFilterExpanded        = "pixcurate.filter.xmp.expanded"
    static let presetExpanded           = "pixcurate.filter.preset.expanded"
    static let fileTypeFilter           = "pixcurate.fileTypeFilter"
    static let formatFilterExpanded     = "pixcurate.filter.format.expanded"
    static let folderExpanded           = "pixcurate.folder.expanded"
    static let filterExpanded           = "pixcurate.filter.section.expanded"
    static let collectionExpanded       = "pixcurate.collection.expanded"
    static let copyExpanded             = "pixcurate.copy.expanded"
    static let gridWindowWidth          = "pixcurate.window.gridWidth"
    static let listWindowWidth          = "pixcurate.window.listWidth"
    static let annualFilterDays         = "pixcurate.annualFilterDays"
}

// MARK: - DateFilterMode

enum DateFilterMode: String {
    case off    = "off"     // 撮影日フィルターなし
    case annual = "annual"  // 例年の今頃
    case range  = "range"   // 期間指定（From/To）
}

// MARK: - FileTypeFilter

enum FileTypeFilter: String, CaseIterable {
    case rawOnly  = "RAWのみ"
    case jpegOnly = "JPEGのみ"
    case both     = "両方"

    var shortLabel: String {
        switch self {
        case .rawOnly:  return "RAW"
        case .jpegOnly: return "JPEG"
        case .both:     return "両方"
        }
    }
    var icon: String {
        switch self {
        case .rawOnly:  return "r.square"
        case .jpegOnly: return "j.square"
        case .both:     return "square.stack"
        }
    }
    var iconFill: String {
        switch self {
        case .rawOnly:  return "r.square.fill"
        case .jpegOnly: return "j.square.fill"
        case .both:     return "square.stack.fill"
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
class FileListViewModel {
    var allFiles: [PhotoFile] = []
    var filteredFiles: [PhotoFile] = []
    var isLoading = false
    var isIndexing = false          // バックグラウンド差分スキャン中
    var indexStatus = ""            // "DB: 123件" など
    var logLines: [String] = []
    var isRunning = false
    var copyTotal: Int = 0
    var copyCurrent: Int = 0
    var exiftoolMissing = false

    // MARK: - Load（DB優先 → 差分スキャン）

    func load(from url: URL, minRating: Int) {
        isLoading = true
        allFiles = []
        filteredFiles = []
        indexStatus = ""

        Task.detached {
            // 1. DBに既存データがあれば即ロード
            let cached = IndexService.loadFromDB(folder: url)
            let hasCached = !cached.isEmpty

            await MainActor.run { [weak self] in
                guard let self else { return }
                if hasCached {
                    allFiles = cached
                    applyFilter(minRating: minRating)
                    isLoading = false
                    isIndexing = true
                    indexStatus = "DB: \(cached.count)件（更新確認中…）"
                }
            }

            // 2. バックグラウンドで差分スキャン
            let (files, scanResult) = IndexService.fullScan(folder: url)

            await MainActor.run { [weak self] in
                guard let self else { return }
                allFiles = files
                applyFilter(minRating: minRating)
                isLoading = false
                isIndexing = false
                indexStatus = "DB: \(files.count)件"
                if scanResult.added > 0 || scanResult.updated > 0 || scanResult.removed > 0 {
                    let parts = [
                        scanResult.added   > 0 ? "新規\(scanResult.added)件"   : nil,
                        scanResult.updated > 0 ? "更新\(scanResult.updated)件" : nil,
                        scanResult.removed > 0 ? "削除\(scanResult.removed)件" : nil,
                    ].compactMap { $0 }.joined(separator: " / ")
                    indexStatus = "DB: \(files.count)件（\(parts)）"
                }
            }
        }
    }

    // MARK: - 再スキャン（強制フルスキャン）

    func rescan(from url: URL, minRating: Int) {
        guard !isIndexing else { return }
        isIndexing = true
        indexStatus = "再スキャン中…"

        Task.detached {
            let (files, result) = IndexService.fullScan(folder: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                allFiles = files
                applyFilter(minRating: minRating)
                isIndexing = false
                indexStatus = "DB: \(files.count)件（新規\(result.added) 更新\(result.updated) 削除\(result.removed)）"
            }
        }
    }

    // MARK: - DB再構築（全削除→フルスキャン）

    func rebuildDB(from url: URL, minRating: Int) {
        guard !isIndexing else { return }
        isIndexing = true
        isLoading = true
        allFiles = []
        filteredFiles = []
        indexStatus = "DB再構築中…"

        Task.detached {
            DatabaseService.shared.deleteAll(under: url)
            let (files, result) = IndexService.fullScan(folder: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                allFiles = files
                applyFilter(minRating: minRating)
                isLoading = false
                isIndexing = false
                indexStatus = "DB再構築完了: \(files.count)件"
            }
        }
    }

    var locationFilter: Set<UUID> = []
    var shotDateFrom: Date? = nil      // nilなら無効
    var shotDateTo: Date? = nil
    var xmpSinceFilter: Date? = nil   // nilなら無効
    var fileTypeFilter: FileTypeFilter = .rawOnly
    var annualFilterDays: Int? = nil   // nilなら無効。非nilのとき例年の今頃フィルターが有効

    // MARK: - Collection mode
    var isCollectionMode: Bool = false

    func loadCollection(_ collection: PhotoCollection, minRating: Int) {
        isCollectionMode = true
        isLoading = true
        allFiles = []
        filteredFiles = []
        indexStatus = "\(collection.name) 読み込み中…"

        Task.detached {
            let files = CollectionStore.shared.loadFiles(in: collection)
            await MainActor.run { [weak self] in
                guard let self else { return }
                allFiles = files
                applyFilter(minRating: minRating)
                isLoading = false
                indexStatus = "\(files.count)件"
            }
        }
    }

    func exitCollectionMode(srcURL: URL?, minRating: Int) {
        isCollectionMode = false
        if let url = srcURL {
            load(from: url, minRating: minRating)
        } else {
            allFiles = []
            filteredFiles = []
            indexStatus = ""
        }
    }

    // MARK: - List sort
    var listSortColumn: ListColumn? = nil   // nil = ファイル名
    var listSortAscending: Bool = true

    func toggleListSort(column: ListColumn?, minRating: Int) {
        if listSortColumn == column {
            if listSortAscending {
                listSortAscending = false
            } else {
                listSortColumn = nil
                listSortAscending = true
            }
        } else {
            listSortColumn = column
            listSortAscending = true
        }
        applyFilter(minRating: minRating)
    }

    func updateRating(for rawURL: URL, rating: Int?) {
        update(rawURL: rawURL) { $0.rating = rating }
    }

    func updateTags(for rawURL: URL, tags: [String]) {
        update(rawURL: rawURL) { $0.tags = tags }
    }

    func updateLocation(for rawURL: URL, locationId: UUID?, locationPath: LocationPath?) {
        update(rawURL: rawURL) {
            $0.locationId = locationId
            $0.locationPath = locationPath
        }
    }

    private func update(rawURL: URL, mutation: (inout PhotoFile) -> Void) {
        if let idx = allFiles.firstIndex(where: { $0.rawURL == rawURL }) {
            mutation(&allFiles[idx])
            let file = allFiles[idx]
            Task.detached { DatabaseService.shared.upsert(file, xmpModifiedAt: nil) }
        }
        if let idx = filteredFiles.firstIndex(where: { $0.rawURL == rawURL }) {
            mutation(&filteredFiles[idx])
        }
    }

    // Each inner array = one OR-group; outer array connected by AND
    var filterGroups: [[String]] = []

    func applyFilter(minRating: Int) {
        let cal = Calendar.current
        filteredFiles = allFiles.filter { file in
            let typeOK: Bool
            switch fileTypeFilter {
            case .rawOnly:  typeOK = !file.isJpeg
            case .jpegOnly: typeOK = file.isJpeg
            case .both:     typeOK = true
            }
            guard typeOK else { return false }
            let ratingOK = minRating == 0 || (file.rating ?? 0) >= minRating
            let tagOK = filterGroups.isEmpty || filterGroups.allSatisfy { group in
                group.isEmpty || group.contains { file.tags.contains($0) }
            }
            let locationOK = locationFilter.isEmpty || (file.locationId.map { locationFilter.contains($0) } ?? false)
            let shotDateOK: Bool
            if let days = annualFilterDays {
                // 例年の今頃フィルター：年をまたいで月日の近さで判定
                guard let shot = file.shotDate else { return false }
                shotDateOK = Self.isWithinAnnualRange(shot, days: days, cal: cal)
            } else if shotDateFrom != nil || shotDateTo != nil {
                guard let shot = file.shotDate else { return false }
                let shotDay = cal.startOfDay(for: shot)
                if let from = shotDateFrom, shotDay < cal.startOfDay(for: from) { return false }
                if let to = shotDateTo, shotDay > cal.startOfDay(for: to) { return false }
                shotDateOK = true
            } else {
                shotDateOK = true
            }
            let xmpOK: Bool
            if let since = xmpSinceFilter {
                let sinceDay = cal.startOfDay(for: since)
                xmpOK = file.xmpModifiedAt.map { cal.startOfDay(for: $0) >= sinceDay } ?? false
            } else {
                xmpOK = true
            }
            return ratingOK && tagOK && locationOK && shotDateOK && xmpOK
        }
        applyListSort()
    }

    /// 月日だけを見て「今日から±days日以内か」を判定（年をまたぐ場合も正しく処理）
    private static func isWithinAnnualRange(_ date: Date, days: Int, cal: Calendar) -> Bool {
        let today = Date()
        let todayYear = cal.component(.year, from: today)
        // 撮影日の月日を今年に当てはめた日付を生成
        var comps = cal.dateComponents([.month, .day], from: date)
        comps.year = todayYear
        guard let normalized = cal.date(from: comps) else { return false }
        let diff = abs(cal.dateComponents([.day], from: cal.startOfDay(for: normalized),
                                                  to: cal.startOfDay(for: today)).day ?? Int.max)
        // 年末年始をまたぐケース（例：今日1/5、撮影日12/28 → 差8日）
        let yearLen = cal.range(of: .day, in: .year, for: today)?.count ?? 365
        return min(diff, yearLen - diff) <= days
    }

    private func applyListSort() {
        let col = listSortColumn
        let asc = listSortAscending
        switch col {
        case nil:
            filteredFiles.sort { asc ? $0.filename < $1.filename : $0.filename > $1.filename }
        case .shotDate:
            filteredFiles.sort {
                (asc ? $0.shotDate ?? .distantPast < $1.shotDate ?? .distantPast
                     : $0.shotDate ?? .distantPast > $1.shotDate ?? .distantPast)
            }
        case .rating:
            filteredFiles.sort {
                let a = $0.rating ?? -1, b = $1.rating ?? -1
                return asc ? a < b : a > b
            }
        case .location:
            filteredFiles.sort {
                let a = $0.locationPath.map { $0.sublocation ?? $0.city ?? $0.province ?? "" } ?? ""
                let b = $1.locationPath.map { $0.sublocation ?? $0.city ?? $0.province ?? "" } ?? ""
                return asc ? a < b : a > b
            }
        case .tags:
            filteredFiles.sort {
                let a = $0.tags.first ?? "", b = $1.tags.first ?? ""
                return asc ? a < b : a > b
            }
        case .xmpDate:
            filteredFiles.sort {
                (asc ? $0.xmpModifiedAt ?? .distantPast < $1.xmpModifiedAt ?? .distantPast
                     : $0.xmpModifiedAt ?? .distantPast > $1.xmpModifiedAt ?? .distantPast)
            }
        default:
            filteredFiles.sort { $0.filename < $1.filename }
        }
    }

    func runCopy(to dst: URL, keepStructure: Bool, baseURL: URL, dryRun: Bool) {
        logLines = []
        isRunning = true
        copyTotal = filteredFiles.count
        copyCurrent = 0
        let files = filteredFiles

        Task.detached { [weak self] in
            guard let self else { return }
            let service = CopyService()
            let result = service.copy(
                files: files,
                to: dst,
                keepStructure: keepStructure,
                baseURL: baseURL,
                dryRun: dryRun,
                log: { line in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.logLines.append(line)
                    }
                },
                onProgress: { current in
                    Task { @MainActor [weak self] in
                        self?.copyCurrent = current
                    }
                }
            )
            let summary: [String] = {
                var lines = ["══════════════════════════════════"]
                lines.append(dryRun
                    ? "✅ プレビュー対象  : \(result.copied) ファイル"
                    : "✅ コピー完了      : \(result.copied) ファイル")
                lines.append("⏭  スキップ（同一）: \(result.skipped) ファイル")
                if result.errors > 0 { lines.append("❌ エラー          : \(result.errors) ファイル") }
                lines.append("══════════════════════════════════")
                return lines
            }()
            let shouldNotify = !dryRun
            let copied = result.copied, skipped = result.skipped, errors = result.errors
            await MainActor.run { [weak self] in
                guard let self else { return }
                logLines.append(contentsOf: summary)
                copyCurrent = copyTotal
                isRunning = false
            }
            if shouldNotify {
                NotificationService.sendCopyComplete(copied: copied, skipped: skipped, errors: errors)
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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showDisplaySettings = false
    @State private var showCopyConfirm = false
    @State private var showRebuildConfirm = false        // メニュー「DB再構築…」から
    @State private var deleteConfirmCollection: PhotoCollection? = nil
    @State private var deleteConfirmPreset: FilterPreset?        = nil
    @State private var fileTypeFilter: FileTypeFilter = FileTypeFilter(rawValue: UserDefaults.standard.string(forKey: Keys.fileTypeFilter) ?? "") ?? .rawOnly
    @State private var ratingFilterExpanded    = UserDefaults.standard.object(forKey: Keys.ratingFilterExpanded)    as? Bool ?? true
    @State private var tagFilterExpanded       = UserDefaults.standard.object(forKey: Keys.tagFilterExpanded)       as? Bool ?? true
    @State private var locationFilterExpanded  = UserDefaults.standard.object(forKey: Keys.locationFilterExpanded)  as? Bool ?? true
    @State private var shotDateFilterExpanded  = UserDefaults.standard.object(forKey: Keys.shotDateFilterExpanded)  as? Bool ?? true
    @State private var dateFilterMode: DateFilterMode = DateFilterMode(rawValue: UserDefaults.standard.string(forKey: Keys.dateFilterMode) ?? "") ?? .off
    @State private var shotDateFrom: Date      = UserDefaults.standard.object(forKey: Keys.shotDateFrom) as? Date ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var shotDateTo: Date        = UserDefaults.standard.object(forKey: Keys.shotDateTo)   as? Date ?? Date()
    @State private var annualFilterDays: Int   = UserDefaults.standard.object(forKey: Keys.annualFilterDays) as? Int ?? 14
    @State private var xmpFilterExpanded       = UserDefaults.standard.object(forKey: Keys.xmpFilterExpanded)       as? Bool ?? true
    @State private var useXmpSince: Bool = UserDefaults.standard.bool(forKey: Keys.useXmpSince)
    @State private var xmpSinceDate: Date = UserDefaults.standard.object(forKey: Keys.xmpSinceDate) as? Date
        ?? Calendar.current.startOfDay(for: Date())
    @State private var presetExpanded        = UserDefaults.standard.object(forKey: Keys.presetExpanded)        as? Bool ?? true
    @State private var formatFilterExpanded  = UserDefaults.standard.object(forKey: Keys.formatFilterExpanded)  as? Bool ?? true
    @State private var activePresetId: UUID?
    @State private var showSavePreset = false
    @State private var presetName = ""
    @State private var editingPreset: FilterPreset?
    // セクション折りたたみ
    @State private var folderExpanded     = UserDefaults.standard.object(forKey: Keys.folderExpanded)     as? Bool ?? true
    @State private var filterExpanded     = UserDefaults.standard.object(forKey: Keys.filterExpanded)     as? Bool ?? true
    @State private var collectionExpanded = UserDefaults.standard.object(forKey: Keys.collectionExpanded) as? Bool ?? true
    @State private var copyExpanded       = UserDefaults.standard.object(forKey: Keys.copyExpanded)       as? Bool ?? true
    // モード別ウィンドウ幅の記憶
    @State private var savedGridWidth: CGFloat = UserDefaults.standard.object(forKey: Keys.gridWindowWidth) as? CGFloat ?? 1100
    @State private var savedListWidth: CGFloat = UserDefaults.standard.object(forKey: Keys.listWindowWidth) as? CGFloat ?? 1500
    @State private var activeCollection: PhotoCollection?
    @State private var showNewCollection = false
    @State private var newCollectionName = ""
    @State private var pendingCollectionFiles: [PhotoFile] = []
    @State private var editingCollection: PhotoCollection?
    @State private var editingCollectionName = ""
    @State private var exportConfirm: (collection: PhotoCollection, dst: URL)? = nil
    @Environment(LocationStore.self) private var locationStore
    @Environment(DisplaySettings.self) private var displaySettings
    @Environment(FilterPresetStore.self) private var presetStore
    @Environment(CollectionStore.self) private var collectionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
                .frame(minWidth: 240)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
        } detail: {
            detailView
        }
        .frame(minWidth: 740, minHeight: 520)
        .onAppear {
            columnVisibility = .all
            NotificationService.requestPermission()
        }
        .background(WindowAccessor { window in
            window.setFrameAutosaveName("PixCurateMain")
        })
        .onChange(of: srcURL, initial: true) { _, newVal in
            BookmarkStore.save(url: newVal, key: Keys.srcPath)
            if let url = newVal {
                vm.xmpSinceFilter = useXmpSince ? xmpSinceDate : nil
                vm.locationFilter = selectedLocationIds
                vm.filterGroups = filterGroups.map { Array($0.tagNames) }
                vm.fileTypeFilter = fileTypeFilter
                switch dateFilterMode {
                case .off:
                    vm.annualFilterDays = nil; vm.shotDateFrom = nil; vm.shotDateTo = nil
                case .annual:
                    vm.annualFilterDays = annualFilterDays; vm.shotDateFrom = nil; vm.shotDateTo = nil
                case .range:
                    vm.annualFilterDays = nil; vm.shotDateFrom = shotDateFrom; vm.shotDateTo = shotDateTo
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .rescanRequested)) { _ in
            if let url = srcURL { vm.rescan(from: url, minRating: minRating) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rebuildRequested)) { _ in
            if srcURL != nil { showRebuildConfirm = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetWindowState)) { _ in
            resetWindowState()
        }
        .onChange(of: displaySettings.viewMode) { _, newMode in
            resizeWindowForMode(newMode)
        }
        .alert("エクスポートの確認", isPresented: Binding(
            get: { exportConfirm != nil },
            set: { if !$0 { exportConfirm = nil } }
        )) {
            Button("キャンセル", role: .cancel) { exportConfirm = nil }
            Button("コピー実行") {
                if let ec = exportConfirm {
                    runExport(collection: ec.collection, dst: ec.dst)
                }
                exportConfirm = nil
            }
            .disabled(vm.filteredFiles.allSatisfy { $0.isOffline })
        } message: {
            Text(exportConfirmMessage)
        }
        .alert("新規コレクション", isPresented: $showNewCollection) {
            TextField("コレクション名", text: $newCollectionName)
            Button("キャンセル", role: .cancel) {}
            Button("作成") {
                let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let col = collectionStore.add(name: name)
                if !pendingCollectionFiles.isEmpty {
                    collectionStore.addFiles(pendingCollectionFiles, to: col)
                    pendingCollectionFiles = []
                }
            }
        } message: { Text("名前を入力してください") }
        .alert("コレクション名の変更", isPresented: Binding(
            get: { editingCollection != nil },
            set: { if !$0 { editingCollection = nil } }
        )) {
            TextField("コレクション名", text: $editingCollectionName)
            Button("キャンセル", role: .cancel) { editingCollection = nil }
            Button("変更") { commitCollectionRename() }
        } message: { Text("新しい名前を入力してください") }
        .alert("DB再構築の確認", isPresented: $showRebuildConfirm) {
            Button("キャンセル", role: .cancel) {}
            Button("再構築", role: .destructive) {
                if let url = srcURL { vm.rebuildDB(from: url, minRating: minRating) }
            }
        } message: {
            Text("DBを全削除してすべてのファイルを再スキャンします。件数が多い場合は時間がかかります。")
        }
        .alert("コレクションを削除", isPresented: Binding(
            get: { deleteConfirmCollection != nil },
            set: { if !$0 { deleteConfirmCollection = nil } }
        )) {
            Button("キャンセル", role: .cancel) { deleteConfirmCollection = nil }
            Button("削除", role: .destructive) {
                if let col = deleteConfirmCollection {
                    if activeCollection?.id == col.id {
                        activeCollection = nil
                        vm.exitCollectionMode(srcURL: srcURL, minRating: minRating)
                    }
                    collectionStore.delete(col)
                    deleteConfirmCollection = nil
                }
            }
        } message: {
            if let col = deleteConfirmCollection {
                Text("「\(col.name)」を削除します。この操作は元に戻せません。")
            }
        }
        .alert("プリセットを削除", isPresented: Binding(
            get: { deleteConfirmPreset != nil },
            set: { if !$0 { deleteConfirmPreset = nil } }
        )) {
            Button("キャンセル", role: .cancel) { deleteConfirmPreset = nil }
            Button("削除", role: .destructive) {
                if let preset = deleteConfirmPreset {
                    presetStore.delete(preset)
                    deleteConfirmPreset = nil
                }
            }
        } message: {
            if let preset = deleteConfirmPreset {
                Text("プリセット「\(preset.name)」を削除します。この操作は元に戻せません。")
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    if folderExpanded {
                        FolderPickerRow(label: "コピー元", url: $srcURL)
                            .listRowInsets(SidebarLayout.rowInsets)
                        FolderPickerRow(label: "コピー先", url: $dstURL)
                            .listRowInsets(SidebarLayout.rowInsets)
                    }
                } header: {
                    collapsibleHeader("フォルダ", color: .blue, expanded: folderExpanded, toggle: {
                        folderExpanded.toggle()
                        UserDefaults.standard.set(folderExpanded, forKey: Keys.folderExpanded)
                    }, key: Keys.folderExpanded)
                }

                Section {
                    if filterExpanded {
                    // フォーマット
                    DisclosureGroup(isExpanded: $formatFilterExpanded) {
                        HStack(spacing: 0) {
                            ForEach(FileTypeFilter.allCases, id: \.self) { t in
                                let selected = fileTypeFilter == t
                                Button {
                                    fileTypeFilter = t
                                    UserDefaults.standard.set(t.rawValue, forKey: Keys.fileTypeFilter)
                                    vm.fileTypeFilter = t
                                    vm.applyFilter(minRating: minRating)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: selected ? t.iconFill : t.icon)
                                            .font(.title2)
                                        Text(t.shortLabel)
                                            .font(.caption)
                                            .fontWeight(selected ? .semibold : .regular)
                                    }
                                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, SidebarLayout.itemVPad)
                    } label: {
                        filterLabel("フォーマット", icon: "photo.stack", color: .cyan)
                    }
                    .listRowInsets(SidebarLayout.rowInsets)
                    .onChange(of: formatFilterExpanded) { _, v in
                        UserDefaults.standard.set(v, forKey: Keys.formatFilterExpanded)
                    }

                    // 評価
                    DisclosureGroup(isExpanded: $ratingFilterExpanded) {
                        StarPickerView(selection: $minRating)
                            .padding(.vertical, 2)
                    } label: {
                        filterLabel("評価", icon: "star.fill", color: .yellow)
                    }
                    .listRowInsets(SidebarLayout.rowInsets)
                    .onChange(of: ratingFilterExpanded) { _, v in
                        UserDefaults.standard.set(v, forKey: Keys.ratingFilterExpanded)
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
                        .listRowInsets(SidebarLayout.rowInsets)
                        .onChange(of: tagFilterExpanded) { _, v in
                            UserDefaults.standard.set(v, forKey: Keys.tagFilterExpanded)
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
                        .listRowInsets(SidebarLayout.rowInsets)
                        .onChange(of: locationFilterExpanded) { _, v in
                            UserDefaults.standard.set(v, forKey: Keys.locationFilterExpanded)
                        }
                    }

                    // 撮影日
                    DisclosureGroup(isExpanded: $shotDateFilterExpanded) {
                        VStack(alignment: .leading, spacing: SidebarLayout.contentSpacing) {

                            // ── モード切替（セグメント） ─────────────────
                            HStack {
                                Picker("", selection: $dateFilterMode) {
                                    Image(systemName: "minus")
                                        .help("フィルターなし")
                                        .tag(DateFilterMode.off)
                                    Image(systemName: "clock.arrow.circlepath")
                                        .help("例年の今頃")
                                        .tag(DateFilterMode.annual)
                                    Image(systemName: "calendar")
                                        .help("期間指定")
                                        .tag(DateFilterMode.range)
                                }
                                .pickerStyle(.segmented)
                                .fixedSize()
                                Spacer()
                            }
                            .onChange(of: dateFilterMode) { _, v in
                                UserDefaults.standard.set(v.rawValue, forKey: Keys.dateFilterMode)
                                applyDateFilter()
                            }

                            // ── 例年の今頃パネル ─────────────────────────
                            if dateFilterMode == .annual {
                                HStack(spacing: 6) {
                                    Text("前後")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    TextField("", value: $annualFilterDays, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 36)
                                        .multilineTextAlignment(.trailing)
                                        .onSubmit {
                                            annualFilterDays = max(0, min(annualFilterDays, 99))
                                            UserDefaults.standard.set(annualFilterDays, forKey: Keys.annualFilterDays)
                                            applyDateFilter()
                                        }
                                    Text("日間")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        annualFilterDays = max(0, min(annualFilterDays, 99))
                                        UserDefaults.standard.set(annualFilterDays, forKey: Keys.annualFilterDays)
                                        applyDateFilter()
                                    } label: {
                                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color.teal)
                                            .symbolRenderingMode(.hierarchical)
                                    }
                                    .buttonStyle(.plain)
                                    .help("日数を適用して絞り込む（0〜99日）")
                                }
                            }

                            // ── 期間指定パネル ───────────────────────────
                            if dateFilterMode == .range {
                                HStack(spacing: 6) {
                                    Text("From")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, alignment: .leading)
                                    DatePicker("", selection: $shotDateFrom, displayedComponents: .date)
                                        .labelsHidden()
                                        .datePickerStyle(.compact)
                                        .onChange(of: shotDateFrom) { _, v in
                                            UserDefaults.standard.set(v, forKey: Keys.shotDateFrom)
                                            applyDateFilter()
                                        }
                                }
                                HStack(spacing: 6) {
                                    Text("To")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, alignment: .leading)
                                    DatePicker("", selection: $shotDateTo, displayedComponents: .date)
                                        .labelsHidden()
                                        .datePickerStyle(.compact)
                                        .onChange(of: shotDateTo) { _, v in
                                            UserDefaults.standard.set(v, forKey: Keys.shotDateTo)
                                            applyDateFilter()
                                        }
                                }
                            }
                        }
                        .padding(.vertical, SidebarLayout.itemVPad)
                    } label: {
                        filterLabel("撮影日", icon: "camera", color: .teal)
                    }
                    .listRowInsets(SidebarLayout.rowInsets)
                    .onChange(of: shotDateFilterExpanded) { _, v in
                        UserDefaults.standard.set(v, forKey: Keys.shotDateFilterExpanded)
                    }

                    // XMP更新日
                    DisclosureGroup(isExpanded: $xmpFilterExpanded) {
                        VStack(alignment: .leading, spacing: SidebarLayout.contentSpacing) {
                            Toggle("更新日フィルター", isOn: $useXmpSince)
                                .font(.callout)
                                .onChange(of: useXmpSince) { _, v in
                                    UserDefaults.standard.set(v, forKey: Keys.useXmpSince)
                                    applyXmpFilter()
                                }
                            if useXmpSince {
                                HStack(spacing: SidebarLayout.itemHPad) {
                                    DatePicker("", selection: $xmpSinceDate, displayedComponents: .date)
                                        .labelsHidden()
                                        .datePickerStyle(.compact)
                                        .onChange(of: xmpSinceDate) { _, v in
                                            UserDefaults.standard.set(v, forKey: Keys.xmpSinceDate)
                                            applyXmpFilter()
                                        }
                                    Text("以降に更新した画像")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, SidebarLayout.itemVPad)
                    } label: {
                        filterLabel("更新日", icon: "calendar.badge.clock", color: .orange)
                    }
                    .listRowInsets(SidebarLayout.rowInsets)
                    .onChange(of: xmpFilterExpanded) { _, v in
                        UserDefaults.standard.set(v, forKey: Keys.xmpFilterExpanded)
                    }

                    // プリセット（フィルターの一部として配置）
                    DisclosureGroup(isExpanded: $presetExpanded) {
                        if presetStore.presets.isEmpty {
                            Text("保存済みのプリセットはありません")
                                .font(.callout)
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
                                                  : "bookmark")
                                                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                                                .font(.callout)
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
                                            .font(.callout)
                                    }
                                    .buttonStyle(.borderless)
                                    Button {
                                        deleteConfirmPreset = preset
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.callout)
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, SidebarLayout.itemVPad)
                                .padding(.horizontal, SidebarLayout.itemHPad)
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
                        filterLabel("プリセット", icon: "bookmark.fill", color: .indigo)
                    }
                    .listRowInsets(SidebarLayout.rowInsets)
                    .onChange(of: presetExpanded) { _, v in
                        UserDefaults.standard.set(v, forKey: Keys.presetExpanded)
                    }
                    } // if filterExpanded
                } header: {
                    collapsibleHeader("フィルター", color: .orange, expanded: filterExpanded, toggle: {
                        filterExpanded.toggle()
                        UserDefaults.standard.set(filterExpanded, forKey: Keys.filterExpanded)
                    }, key: Keys.filterExpanded)
                }

                Section {
                    collectionSection
                        .listRowInsets(SidebarLayout.rowInsets)
                } header: {
                    collapsibleHeader("コレクション", color: .purple, expanded: collectionExpanded, toggle: {
                        collectionExpanded.toggle()
                        UserDefaults.standard.set(collectionExpanded, forKey: Keys.collectionExpanded)
                    }, key: Keys.collectionExpanded, trailing: {
                        AnyView(
                            Button {
                                newCollectionName = ""
                                pendingCollectionFiles = []
                                showNewCollection = true
                            } label: {
                                Image(systemName: "plus").font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("新規コレクション")
                        )
                    })
                }

                Section {
                    if copyExpanded {
                        Toggle("フォルダ構造を維持", isOn: $keepStructure)
                            .listRowInsets(SidebarLayout.rowInsets)
                            .onChange(of: keepStructure) { _, v in
                                UserDefaults.standard.set(v, forKey: Keys.keepStructure)
                            }
                        copySection
                            .listRowInsets(SidebarLayout.rowInsets)
                    }
                } header: {
                    collapsibleHeader("コピー", color: .green, expanded: copyExpanded, toggle: {
                        copyExpanded.toggle()
                        UserDefaults.standard.set(copyExpanded, forKey: Keys.copyExpanded)
                    }, key: Keys.copyExpanded)
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

    // MARK: - Collection section

    @ViewBuilder
    private var collectionSection: some View {
        if collectionExpanded {
        if collectionStore.collections.isEmpty {
            Text("コレクションなし")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(collectionStore.collections) { col in
                let isActive = activeCollection?.id == col.id
                HStack(spacing: 6) {
                    Button {
                        if isActive {
                            activeCollection = nil
                            vm.exitCollectionMode(srcURL: srcURL, minRating: minRating)
                        } else {
                            activeCollection = col
                            vm.loadCollection(col, minRating: minRating)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isActive
                                  ? "rectangle.stack.fill"
                                  : "rectangle.stack")
                                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                                .font(.callout)
                            Text(col.name)
                                .font(.callout)
                                .fontWeight(isActive ? .semibold : .regular)
                            Spacer()
                            Text("\(col.fileCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        editingCollection = col
                        editingCollectionName = col.name
                    } label: {
                        Image(systemName: "square.and.pencil").font(.callout)
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive) {
                        deleteConfirmCollection = col
                    } label: {
                        Image(systemName: "trash")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, SidebarLayout.itemVPad)
                .padding(.horizontal, SidebarLayout.itemHPad)
                .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        }
    }

    // MARK: - Sidebar layout constants

    private enum SidebarLayout {
        /// セクションヘッダー（フォルダ/フィルター等）の縦パディング
        static let headerVPad:    CGFloat   = 3
        /// 全 List 行の insets（上下対称）
        static let rowInsets:     EdgeInsets = EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        /// アイテム行の内部縦パディング（プリセット・コレクション等）
        static let itemVPad:      CGFloat   = 3
        /// アイテム行の内部横パディング
        static let itemHPad:      CGFloat   = 6
        /// 展開コンテンツ内の VStack spacing
        static let contentSpacing: CGFloat  = 6
    }

    // MARK: - Sidebar helper views

    /// レベル1：フォルダ/フィルター/コレクション/コピー
    private func collapsibleHeader(_ title: String, color: Color, expanded: Bool, toggle: @escaping () -> Void, key: String, trailing: (() -> AnyView)? = nil) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .textCase(nil)
                .foregroundStyle(color)
            Spacer()
            if let trailing { trailing() }
            Button { toggle() } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.callout)
                    .foregroundStyle(color.opacity(0.7))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, SidebarLayout.headerVPad)
        .background(color.opacity(0.10).padding(.horizontal, -50))
    }

    /// レベル2：評価/タグ/撮影地/撮影日/更新日/プリセット（DisclosureGroup ラベル）
    private func filterLabel(_ title: String, icon: String, color: Color) -> some View {
        Label {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }

    /// sectionHeader は filterLabel に統合済み（旧互換用・不使用）
    private func sectionHeader(_ title: String, color: Color = .secondary) -> some View {
        Text(title)
            .font(.body)
            .fontWeight(.semibold)
            .textCase(nil)
            .foregroundStyle(color)
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

    private func applyDateFilter() {
        switch dateFilterMode {
        case .off:
            vm.annualFilterDays = nil
            vm.shotDateFrom = nil
            vm.shotDateTo   = nil
        case .annual:
            let days = max(0, min(annualFilterDays, 99))
            vm.annualFilterDays = days
            vm.shotDateFrom = nil
            vm.shotDateTo   = nil
        case .range:
            vm.annualFilterDays = nil
            vm.shotDateFrom = shotDateFrom
            vm.shotDateTo   = shotDateTo
        }
        vm.applyFilter(minRating: minRating)
    }

    private func applyXmpFilter(clearPreset: Bool = true) {
        vm.xmpSinceFilter = useXmpSince ? xmpSinceDate : nil
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

    private func applyRatingToSelection(rating: Int?) {
        let files = vm.filteredFiles.filter { selection.contains($0.id) }
        guard !files.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            for file in files {
                _ = XMPService.writeRating(to: file.xmpURL, rating: rating ?? 0)
            }
            let updates = files.map { $0.rawURL }
            await MainActor.run {
                for url in updates {
                    vm.updateRating(for: url, rating: rating)
                }
            }
        }
    }

    private var exportConfirmMessage: String {
        guard let ec = exportConfirm else { return "" }
        let files = vm.filteredFiles
        let offlineGroups = collectionStore.offlineGroups(in: files)
        let offlineCount = files.filter(\.isOffline).count
        var lines: [String] = []
        lines.append("コレクション「\(ec.collection.name)」\(files.count) 件")
        lines.append("コピー先: \(ec.dst.path)")
        if !offlineGroups.isEmpty {
            lines.append("")
            lines.append("⚠️ \(offlineCount) 件が見つかりません（スキップされます）:")
            for g in offlineGroups {
                lines.append("  • \(g.volume)（\(g.count) 件）")
            }
            lines.append("該当するディスクを接続してから実行するとすべてコピーできます。")
        }
        return lines.joined(separator: "\n")
    }

    private func commitCollectionRename() {
        guard let col = editingCollection else { return }
        let name = editingCollectionName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { collectionStore.rename(col, to: name) }
        if activeCollection?.id == col.id {
            activeCollection = collectionStore.collections.first { $0.id == col.id }
        }
        editingCollection = nil
    }

    private func exportCollection(_ collection: PhotoCollection) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "エクスポート先を選択"
        panel.message = "「\(collection.name)」のファイルをコピーします"
        guard panel.runModal() == .OK, let dst = panel.url else { return }
        exportConfirm = (collection: collection, dst: dst)
    }

    private func runExport(collection: PhotoCollection, dst: URL) {
        let files = vm.filteredFiles
        vm.logLines = []
        vm.isRunning = true
        vm.copyTotal = files.count
        vm.copyCurrent = 0

        Task.detached {
            let service = CopyService()
            let result = service.copy(
                files: files,
                to: dst,
                keepStructure: false,
                baseURL: dst,
                dryRun: false,
                log: { line in
                    Task { @MainActor in vm.logLines.append(line) }
                },
                onProgress: { current in
                    Task { @MainActor in vm.copyCurrent = current }
                }
            )
            let summary: [String] = {
                var lines = ["══════════════════════════════════"]
                lines.append("✅ コピー完了: \(result.copied) ファイル")
                if result.skipped > 0 { lines.append("⏭  スキップ: \(result.skipped) ファイル") }
                if result.errors  > 0 { lines.append("❌ エラー: \(result.errors) ファイル") }
                lines.append("══════════════════════════════════")
                return lines
            }()
            let copied = result.copied, skipped = result.skipped, errors = result.errors
            await MainActor.run {
                vm.logLines.append(contentsOf: summary)
                vm.copyCurrent = vm.copyTotal
                vm.isRunning = false
            }
            NotificationService.sendCopyComplete(copied: copied, skipped: skipped, errors: errors)
        }
    }

    private func resizeWindowForMode(_ mode: DisplaySettings.ViewMode) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let screen = window.screen ?? NSScreen.main!
        let sf = screen.visibleFrame
        var frame = window.frame

        // 切り替え前のモードのウィンドウ幅を保存
        switch mode {
        case .list:
            savedGridWidth = frame.width
            UserDefaults.standard.set(frame.width, forKey: Keys.gridWindowWidth)
        case .grid:
            savedListWidth = frame.width
            UserDefaults.standard.set(frame.width, forKey: Keys.listWindowWidth)
        }

        // 切り替え先の幅を復元（画面幅でクランプ）
        let targetWidth: CGFloat
        switch mode {
        case .list: targetWidth = min(savedListWidth, sf.width)
        case .grid: targetWidth = min(savedGridWidth, sf.width)
        }

        frame.origin.x = max(sf.minX, frame.origin.x - (targetWidth - frame.width) / 2)
        frame.size.width = targetWidth
        if frame.maxX > sf.maxX { frame.origin.x = sf.maxX - frame.width }
        if frame.minX < sf.minX { frame.origin.x = sf.minX }

        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Excel (xlsx) export

    private func exportXLSX() {
        let panel = NSSavePanel()
        panel.title = "Excelファイルとして保存"
        panel.nameFieldStringValue = "PixCurate_\(Date().csvSuffix).xlsx"
        panel.allowedFileTypes = ["xlsx"]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let files      = vm.filteredFiles
        let activeCols = ListColumn.allCases.filter { displaySettings.listColumns.contains($0) }
        let needsEXIF  = activeCols.contains(where: \.needsEXIF)

        var headers = ["ファイル名"]
        headers += activeCols.map(\.label)

        // Excel 列幅（ファイル名=30、各列は ListColumn.xlsxWidth）
        var colWidths: [Double] = [30]
        colWidths += activeCols.map(\.xlsxWidth)

        Task.detached {
            let dateFmt = DateFormatter()
            dateFmt.locale = Locale(identifier: "ja_JP")
            dateFmt.dateFormat = "yyyy/MM/dd HH:mm"

            var rows: [[String]] = []

            for file in files {
                let exif: EXIFInfo? = needsEXIF ? EXIFService.readEXIFInfo(url: file.rawURL) : nil
                var cols = [file.filename]

                for col in activeCols {
                    switch col {
                    case .shotDate:
                        cols.append(file.shotDate.map { dateFmt.string(from: $0) } ?? "")
                    case .rating:
                        cols.append(file.rating.map { String(repeating: "★", count: $0) } ?? "")
                    case .location:
                        let parts = [file.locationPath?.sublocation,
                                     file.locationPath?.city,
                                     file.locationPath?.province].compactMap { $0 }
                        cols.append(parts.joined(separator: " / "))
                    case .tags:
                        // 複数タグは [タグ名] 形式で連結
                        cols.append(file.tags.map { "[\($0)]" }.joined())
                    case .xmpDate:
                        cols.append(file.xmpModifiedAt.map { dateFmt.string(from: $0) } ?? "")
                    case .camera:
                        let parts = [exif?.cameraMake, exif?.cameraModel].compactMap { $0 }
                        cols.append(parts.joined(separator: " "))
                    case .lens:
                        cols.append(exif?.lensModel ?? "")
                    case .focalLength:
                        cols.append(exif?.focalLength.map { "\(Int($0)) mm" } ?? "")
                    case .aperture:
                        cols.append(exif?.aperture.map { String(format: "f/%.1f", $0) } ?? "")
                    case .shutterSpeed:
                        if let ss = exif?.shutterSpeed {
                            cols.append(ss >= 1
                                ? String(format: "%.1f秒", ss)
                                : "1/\(Int((1.0 / ss).rounded()))秒")
                        } else { cols.append("") }
                    case .iso:
                        cols.append(exif?.iso.map { "\($0)" } ?? "")
                    case .resolution:
                        if let w = exif?.imageWidth, let h = exif?.imageHeight {
                            cols.append("\(w) × \(h)")
                        } else { cols.append("") }
                    }
                }
                rows.append(cols)
            }

            // ── サムネイル収集（各ファイルを 120×90px JPEG に縮小）──────
            var thumbnails: [XLSXThumbnail?] = []
            for file in files {
                if file.isOffline {
                    thumbnails.append(nil)
                } else if let nsImg = await ThumbnailService.thumbnail(for: file.rawURL) {
                    thumbnails.append(xlsxResizedJPEG(nsImg))
                } else {
                    thumbnails.append(nil)
                }
            }

            try? XLSXExporter.write(headers: headers, rows: rows,
                                    columnWidths: colWidths,
                                    thumbnails: thumbnails,
                                    to: url)
        }
    }


    private func resetWindowState() {
        // 表示設定をデフォルトに戻す
        displaySettings.viewMode    = .grid
        displaySettings.thumbSize   = .small
        displaySettings.badgeFont   = .small
        displaySettings.showRating  = true
        displaySettings.showTags    = true
        displaySettings.showLocation = true
        displaySettings.showFilename = true
        displaySettings.showShotDate = true
        displaySettings.save()

        // サイドバーを表示
        columnVisibility = .all

        // ウィンドウを最適サイズ・中央に
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            let size = NSSize(width: 1100, height: 720)
            let screen = window.screen ?? NSScreen.main!
            let sf = screen.visibleFrame
            let origin = CGPoint(x: sf.midX - size.width / 2, y: sf.midY - size.height / 2)
            window.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
        }
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
                        if vm.isIndexing {
                            ProgressView().scaleEffect(0.55)
                            Text(vm.indexStatus)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if !vm.indexStatus.isEmpty {
                            Text(vm.indexStatus)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if let col = activeCollection, !vm.isLoading {
                        Button {
                            exportCollection(col)
                        } label: {
                            Label("エクスポート", systemImage: "square.and.arrow.up")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("コレクションをフォルダにコピー")
                    }
                    if let url = srcURL, !vm.isLoading, !vm.isCollectionMode {
                        Button {
                            vm.rescan(from: url, minRating: minRating)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .disabled(vm.isIndexing)
                        .help("再スキャン")

                    }
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
                    if !vm.filteredFiles.isEmpty {
                        Button {
                            exportXLSX()
                        } label: {
                            Image(systemName: "tablecells.badge.ellipsis")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .help("一覧をExcel（xlsx）に出力")
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

                FileListView(
                    files: vm.filteredFiles,
                    totalCount: vm.allFiles.count,
                    selection: $selection,
                    sortColumn: vm.listSortColumn,
                    sortAscending: vm.listSortAscending,
                    onRateSelected: { applyRatingToSelection(rating: $0) },
                    onSort: { vm.toggleListSort(column: $0, minRating: minRating) },
                    collections: collectionStore.collections,
                    activeCollectionId: activeCollection?.id,
                    onAddToCollection: { col, files in
                        collectionStore.addFiles(files, to: col)
                    },
                    onCreateAndAdd: { files in
                        pendingCollectionFiles = files
                        newCollectionName = ""
                        showNewCollection = true
                    },
                    onRemoveFromCollection: activeCollection.map { col in
                        { files in
                            collectionStore.removeFiles(files, from: col)
                            vm.loadCollection(col, minRating: minRating)
                        }
                    }
                )

                if !vm.logLines.isEmpty || vm.isRunning {
                    Divider()
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            if vm.isRunning {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                                Text("\(vm.copyCurrent) / \(vm.copyTotal) ファイル")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } else {
                                Text("ログ")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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

                        if vm.isRunning && vm.copyTotal > 0 {
                            ProgressView(value: Double(vm.copyCurrent), total: Double(vm.copyTotal))
                                .progressViewStyle(.linear)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 4)
                                .background(.bar)
                        }

                        logView
                    }
                    .frame(height: 180)
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
                Text(label).font(.callout).fontWeight(.medium).foregroundStyle(.secondary)
                if let url {
                    Text(url.path)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .font(.callout)
                        .foregroundStyle(.primary)
                } else {
                    Text("未選択")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { pick() } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
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
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= selection ? "star.fill" : "star")
                    .foregroundStyle(star <= selection ? Color.yellow : Color.secondary.opacity(0.4))
                    .font(.system(size: 14))
                    .onTapGesture {
                        // タップで選択、同じ星を再度タップで1つ減らす
                        selection = (selection == star) ? star - 1 : star
                    }
            }
        }
    }
}

// MARK: - XLSX サムネイルヘルパー

/// NSImage を maxW×maxH px（アスペクト比維持・縮小のみ）の XLSXThumbnail に変換する。
/// CoreGraphics のみ使用 → バックグラウンドスレッドから安全に呼べる。
private func xlsxResizedJPEG(_ image: NSImage, maxW: Int = 120, maxH: Int = 90) -> XLSXThumbnail? {
    guard let cgSrc = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let srcW = cgSrc.width, srcH = cgSrc.height
    guard srcW > 0, srcH > 0 else { return nil }

    // アスペクト比を保って縮小（拡大はしない）
    let scale = min(Double(maxW) / Double(srcW), Double(maxH) / Double(srcH), 1.0)
    let dstW  = max(1, Int(Double(srcW) * scale))
    let dstH  = max(1, Int(Double(srcH) * scale))

    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: dstW, height: dstH,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(cgSrc, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))

    guard let resized = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: resized)
    guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else { return nil }
    return XLSXThumbnail(data: data, width: dstW, height: dstH)
}

// MARK: - Preview

#Preview {
    ContentView()
}

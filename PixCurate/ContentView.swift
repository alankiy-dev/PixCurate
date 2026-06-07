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
    static let ratingFilterMode         = "pixcurate.filter.rating.mode"
    static let tagFilterExpanded        = "pixcurate.filter.tag.expanded"
    static let locationFilterExpanded   = "pixcurate.filter.location.expanded"
    static let xmpFilterExpanded        = "pixcurate.filter.xmp.expanded"
    static let presetExpanded           = "pixcurate.filter.preset.expanded"
    static let fileTypeFilter           = "pixcurate.fileTypeFilter"
    static let tabFilters               = "pixcurate.tabFilters"
    static let formatFilterExpanded     = "pixcurate.filter.format.expanded"
    static let folderExpanded           = "pixcurate.folder.expanded"
    static let filterExpanded           = "pixcurate.filter.section.expanded"
    static let collectionExpanded       = "pixcurate.collection.expanded"
    static let copyExpanded             = "pixcurate.copy.expanded"
    static let gridWindowWidth          = "pixcurate.window.gridWidth"
    static let listWindowWidth          = "pixcurate.window.listWidth"
    static let annualFilterDays         = "pixcurate.annualFilterDays"
    static let listSortColumn           = "pixcurate.listSortColumn"
    static let listSortAscending        = "pixcurate.listSortAscending"
}

// MARK: - DateFilterMode

enum DateFilterMode: String {
    case off    = "off"     // 撮影日フィルターなし
    case annual = "annual"  // 例年の今頃
    case range  = "range"   // 期間指定（From/To）
}

// MARK: - RatingFilterMode

enum RatingFilterMode: String {
    case atLeast = "atLeast"   // N星以上
    case exactly = "exactly"   // N星のみ
}

// MARK: - SourceTab（フォルダ別タブ）

enum SourceTab: Hashable {
    case all                // すべて（全フォルダまとめ）
    case folder(UUID)       // SourceFolder.id
}

// MARK: - TabFilterState（タブごとのフィルター条件スナップショット・案C）

/// フィルター述語に渡す条件一式（タブ別の独立計算に使用）
struct FilterSpec {
    var minRating: Int = 0
    var ratingMode: RatingFilterMode = .atLeast
    var fileTypeFilter: FileTypeFilter = .rawOnly
    var colorLabelFilter: Set<ColorLabel> = []
    var filterGroups: [[String]] = []          // OR-group の配列（AND 連結）
    var locationFilter: Set<UUID> = []
    var annualFilterDays: Int? = nil
    var shotDateFrom: Date? = nil
    var shotDateTo: Date? = nil
    var xmpSinceFilter: Date? = nil
}

/// 1タブ分のフィルター条件をまとめて保持する。タブごとに独立して保持・計算する。
struct TabFilterState {
    var minRating: Int
    var ratingFilterMode: RatingFilterMode
    var filterGroups: [TagFilterGroup]
    var selectedColorLabels: Set<ColorLabel>
    var selectedLocationIds: Set<UUID>
    var fileTypeFilter: FileTypeFilter
    var dateFilterMode: DateFilterMode
    var shotDateFrom: Date
    var shotDateTo: Date
    var annualFilterDays: Int
    var useXmpSince: Bool
    var xmpSinceDate: Date
    var activePresetId: UUID?
}

/// TabFilterState の永続化用 DTO（rawValue/プリミティブのみで Codable）
struct TabFilterDTO: Codable {
    var minRating: Int
    var ratingMode: String
    var tagGroups: [[String]]
    var colorLabels: [String]
    var locationIds: [String]
    var fileType: String
    var dateMode: String
    var shotDateFrom: Date
    var shotDateTo: Date
    var annualDays: Int
    var useXmpSince: Bool
    var xmpSinceDate: Date
    var presetId: String?

    init(_ s: TabFilterState) {
        minRating    = s.minRating
        ratingMode   = s.ratingFilterMode.rawValue
        tagGroups    = s.filterGroups.map { Array($0.tagNames) }
        colorLabels  = s.selectedColorLabels.map { $0.rawValue }
        locationIds  = s.selectedLocationIds.map { $0.uuidString }
        fileType     = s.fileTypeFilter.rawValue
        dateMode     = s.dateFilterMode.rawValue
        shotDateFrom = s.shotDateFrom
        shotDateTo   = s.shotDateTo
        annualDays   = s.annualFilterDays
        useXmpSince  = s.useXmpSince
        xmpSinceDate = s.xmpSinceDate
        presetId     = s.activePresetId?.uuidString
    }

    var state: TabFilterState {
        TabFilterState(
            minRating: minRating,
            ratingFilterMode: RatingFilterMode(rawValue: ratingMode) ?? .atLeast,
            filterGroups: tagGroups.map { names in
                var g = TagFilterGroup(); g.tagNames = Set(names); return g
            },
            selectedColorLabels: Set(colorLabels.compactMap { ColorLabel(rawValue: $0) }),
            selectedLocationIds: Set(locationIds.compactMap { UUID(uuidString: $0) }),
            fileTypeFilter: FileTypeFilter(rawValue: fileType) ?? .rawOnly,
            dateFilterMode: DateFilterMode(rawValue: dateMode) ?? .off,
            shotDateFrom: shotDateFrom,
            shotDateTo: shotDateTo,
            annualFilterDays: annualDays,
            useXmpSince: useXmpSince,
            xmpSinceDate: xmpSinceDate,
            activePresetId: presetId.flatMap { UUID(uuidString: $0) }
        )
    }
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
        case .both:     return "R & J"
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
    var ratingFilterMode: RatingFilterMode = .atLeast

    /// 現在 allFiles に読み込まれているソース（差分ロードの判定に使用）
    var loadedSources: [SourceSpec] = []

    // MARK: - Load（DB優先 → 差分スキャン）

    func load(sources: [SourceSpec], minRating: Int) {
        guard !sources.isEmpty else {
            allFiles = []; filteredFiles = []; indexStatus = ""
            loadedSources = []
            return
        }
        loadedSources = sources
        isLoading = true
        allFiles = []
        filteredFiles = []
        indexStatus = ""
        Task { await ThumbnailService.resetFailedURLs() }

        Task.detached {
            // 1. DBに既存データがあれば即ロード
            let cached = IndexService.loadFromDB(sources: sources)
            let hasCached = !cached.isEmpty

            await MainActor.run { [weak self] in
                guard let self else { return }
                if hasCached {
                    allFiles = cached
                    applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
                    isLoading = false
                    isIndexing = true
                    indexStatus = "DB: \(cached.count)件（更新確認中…）"
                }
            }

            // 2. バックグラウンドで差分スキャン
            let (files, scanResult) = IndexService.fullScan(sources: sources)

            await MainActor.run { [weak self] in
                guard let self else { return }
                allFiles = files
                applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
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

    // MARK: - 差分ロード（フォルダの有効/無効切替時）

    /// フォルダ構成が変わったときの軽量ロード。
    /// - 除外されたフォルダ → スキャンせず DB から再ロード（即時）
    /// - 新たに加わったフォルダ → そのフォルダだけ差分スキャンしてから全体を DB ロード
    func loadIncremental(sources: [SourceSpec], newlyAdded: [SourceSpec], minRating: Int) {
        guard !sources.isEmpty else {
            allFiles = []; filteredFiles = []; indexStatus = ""
            loadedSources = []
            return
        }
        loadedSources = sources
        isLoading = true
        allFiles = []
        filteredFiles = []
        indexStatus = ""
        Task { await ThumbnailService.resetFailedURLs() }

        Task.detached {
            // 1. まず全体を DB から即ロード
            let cached = IndexService.loadFromDB(sources: sources)
            await MainActor.run { [weak self] in
                guard let self else { return }
                allFiles = cached
                applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
                isLoading = false
                if newlyAdded.isEmpty {
                    indexStatus = "DB: \(cached.count)件"
                } else {
                    isIndexing = true
                    indexStatus = "新規フォルダを確認中…"
                }
            }

            // 新規フォルダが無ければ（除外のみ）ここで終了。スキャンしない。
            guard !newlyAdded.isEmpty else { return }

            // 2. 新たに加わったフォルダだけを差分スキャン
            let (_, scanResult) = IndexService.fullScan(sources: newlyAdded)
            // 3. スキャン結果を含めて全体を DB から再ロード
            let merged = IndexService.loadFromDB(sources: sources)

            await MainActor.run { [weak self] in
                guard let self else { return }
                allFiles = merged
                applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
                isIndexing = false
                indexStatus = "DB: \(merged.count)件"
                if scanResult.added > 0 || scanResult.updated > 0 || scanResult.removed > 0 {
                    let parts = [
                        scanResult.added   > 0 ? "新規\(scanResult.added)件"   : nil,
                        scanResult.updated > 0 ? "更新\(scanResult.updated)件" : nil,
                        scanResult.removed > 0 ? "削除\(scanResult.removed)件" : nil,
                    ].compactMap { $0 }.joined(separator: " / ")
                    indexStatus = "DB: \(merged.count)件（\(parts)）"
                }
            }
        }
    }

    // MARK: - 再スキャン（強制フルスキャン）

    func rescan(sources: [SourceSpec], minRating: Int) {
        guard !isIndexing, !sources.isEmpty else { return }
        isIndexing = true
        indexStatus = "再スキャン中…"
        Task { await ThumbnailService.resetFailedURLs() }

        Task.detached {
            let (files, result) = IndexService.fullScan(sources: sources)
            await MainActor.run { [weak self] in
                guard let self else { return }
                allFiles = files
                applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
                isIndexing = false
                indexStatus = "DB: \(files.count)件（新規\(result.added) 更新\(result.updated) 削除\(result.removed)）"
            }
        }
    }

    // MARK: - DB再構築（全削除→フルスキャン）

    func rebuildDB(sources: [SourceSpec], minRating: Int) {
        guard !isIndexing, !sources.isEmpty else { return }
        isIndexing = true
        isLoading = true
        allFiles = []
        filteredFiles = []
        indexStatus = "DB再構築中…"

        Task.detached {
            for spec in sources { DatabaseService.shared.deleteAll(under: spec.url) }
            let (files, result) = IndexService.fullScan(sources: sources)
            await MainActor.run { [weak self] in
                guard let self else { return }
                allFiles = files
                applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
                isLoading = false
                isIndexing = false
                indexStatus = "DB再構築完了: \(files.count)件"
            }
        }
    }

    var colorLabelFilter: Set<ColorLabel> = []
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
                applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
                isLoading = false
                indexStatus = "\(files.count)件"
            }
        }
    }

    func exitCollectionMode(sources: [SourceSpec], minRating: Int) {
        isCollectionMode = false
        if sources.isEmpty {
            allFiles = []; filteredFiles = []; indexStatus = ""
        } else {
            load(sources: sources, minRating: minRating)
        }
    }

    // MARK: - List sort
    var listSortColumn: ListColumn? = {
        guard let raw = UserDefaults.standard.string(forKey: Keys.listSortColumn) else { return nil }
        return ListColumn(rawValue: raw)
    }()
    var listSortAscending: Bool = UserDefaults.standard.object(forKey: Keys.listSortAscending) as? Bool ?? true

    private func saveSortState() {
        UserDefaults.standard.set(listSortColumn?.rawValue, forKey: Keys.listSortColumn)
        UserDefaults.standard.set(listSortAscending, forKey: Keys.listSortAscending)
    }

    /// グリッドのソートUIなど、列・方向を直接指定したいときに使う
    func setSort(column: ListColumn?, ascending: Bool, minRating: Int, ratingMode: RatingFilterMode = .atLeast) {
        listSortColumn = column
        listSortAscending = ascending
        saveSortState()
        applyFilter(minRating: minRating, ratingMode: ratingMode)
    }

    func toggleListSort(column: ListColumn?, minRating: Int, ratingMode: RatingFilterMode = .atLeast) {
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
        saveSortState()
        applyFilter(minRating: minRating, ratingMode: ratingMode)
    }

    func updateRating(for rawURL: URL, rating: Int?) {
        update(rawURL: rawURL) { $0.rating = rating }
    }

    func updateColorLabel(for rawURL: URL, colorLabel: ColorLabel?) {
        update(rawURL: rawURL) { $0.colorLabel = colorLabel }
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

    /// VM の現在のフィルター状態を FilterSpec にまとめる
    private func currentSpec(minRating: Int, ratingMode: RatingFilterMode) -> FilterSpec {
        FilterSpec(
            minRating: minRating,
            ratingMode: ratingMode,
            fileTypeFilter: fileTypeFilter,
            colorLabelFilter: colorLabelFilter,
            filterGroups: filterGroups,
            locationFilter: locationFilter,
            annualFilterDays: annualFilterDays,
            shotDateFrom: shotDateFrom,
            shotDateTo: shotDateTo,
            xmpSinceFilter: xmpSinceFilter
        )
    }

    /// 任意のファイル集合を任意のフィルター条件で絞り込む（タブ別計算で使用）
    func filtered(_ files: [PhotoFile], spec: FilterSpec) -> [PhotoFile] {
        let cal = Calendar.current
        return files.filter { Self.matches($0, spec: spec, cal: cal) }
    }

    /// 任意のファイル集合に対し、条件を満たす件数だけを数える（タブ件数バッジで使用）
    func count(in files: [PhotoFile], spec: FilterSpec) -> Int {
        let cal = Calendar.current
        return files.reduce(0) { Self.matches($1, spec: spec, cal: cal) ? $0 + 1 : $0 }
    }

    /// 1ファイルがフィルター条件を満たすか（純粋関数）
    static func matches(_ file: PhotoFile, spec: FilterSpec, cal: Calendar) -> Bool {
        let typeOK: Bool
        switch spec.fileTypeFilter {
        case .rawOnly:  typeOK = !file.isJpeg
        case .jpegOnly: typeOK = file.isJpeg
        case .both:     typeOK = true
        }
        guard typeOK else { return false }
        let ratingOK: Bool
        if spec.minRating == 0 {
            ratingOK = true
        } else if spec.ratingMode == .exactly {
            ratingOK = (file.rating ?? 0) == spec.minRating
        } else {
            ratingOK = (file.rating ?? 0) >= spec.minRating
        }
        let colorLabelOK = spec.colorLabelFilter.isEmpty || (file.colorLabel.map { spec.colorLabelFilter.contains($0) } ?? false)
        let tagOK = spec.filterGroups.isEmpty || spec.filterGroups.allSatisfy { group in
            group.isEmpty || group.contains { file.tags.contains($0) }
        }
        let locationOK = spec.locationFilter.isEmpty || (file.locationId.map { spec.locationFilter.contains($0) } ?? false)
        let shotDateOK: Bool
        if let days = spec.annualFilterDays {
            // 例年の今頃フィルター：年をまたいで月日の近さで判定
            guard let shot = file.shotDate else { return false }
            shotDateOK = isWithinAnnualRange(shot, days: days, cal: cal)
        } else if spec.shotDateFrom != nil || spec.shotDateTo != nil {
            guard let shot = file.shotDate else { return false }
            let shotDay = cal.startOfDay(for: shot)
            if let from = spec.shotDateFrom, shotDay < cal.startOfDay(for: from) { return false }
            if let to = spec.shotDateTo, shotDay > cal.startOfDay(for: to) { return false }
            shotDateOK = true
        } else {
            shotDateOK = true
        }
        let xmpOK: Bool
        if let since = spec.xmpSinceFilter {
            let sinceDay = cal.startOfDay(for: since)
            xmpOK = file.xmpModifiedAt.map { cal.startOfDay(for: $0) >= sinceDay } ?? false
        } else {
            xmpOK = true
        }
        return ratingOK && colorLabelOK && tagOK && locationOK && shotDateOK && xmpOK
    }

    func applyFilter(minRating: Int, ratingMode: RatingFilterMode = .atLeast) {
        filteredFiles = filtered(allFiles, spec: currentSpec(minRating: minRating, ratingMode: ratingMode))
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

    func runCopy(to dst: URL, keepStructure: Bool, sources: [SourceSpec], dryRun: Bool) {
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
                sources: sources,
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

    @Environment(SourceFolderStore.self) private var sourceFolderStore
    @State private var showSourceFolderManager = false
    @State private var sourcesNeedReload = false   // ダイアログ操作中の再読み込みを閉じたとき1回にまとめる
    @State private var activeTab: SourceTab = .all
    @State private var tabFilters: [SourceTab: TabFilterState] = [:]   // タブごとの独立フィルター（案A）
    @State private var suppressPresetClear = false                     // タブ復元中はプリセット解除を抑止
    @State private var dstURL: URL? = nil   // 起動後にバックグラウンドで復元（メインスレッドをブロックしない）
    @State private var minRating: Int = UserDefaults.standard.object(forKey: Keys.minRating) as? Int ?? 1
    @State private var keepStructure: Bool = UserDefaults.standard.bool(forKey: Keys.keepStructure)
    @State private var selection: Set<UUID> = []
    @State private var filterGroups: [TagFilterGroup] = []
    @State private var selectedColorLabels: Set<ColorLabel> = []
    @State private var selectedLocationIds: Set<UUID> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showDisplaySettings = false
    @State private var showCopyConfirm = false
    @State private var showRebuildConfirm = false        // メニュー「DB再構築…」から
    @State private var deleteConfirmCollection: PhotoCollection? = nil
    @State private var deleteConfirmPreset: FilterPreset?        = nil
    @State private var fileTypeFilter: FileTypeFilter = FileTypeFilter(rawValue: UserDefaults.standard.string(forKey: Keys.fileTypeFilter) ?? "") ?? .rawOnly
    @State private var ratingFilterExpanded    = UserDefaults.standard.object(forKey: Keys.ratingFilterExpanded)    as? Bool ?? true
    @State private var ratingFilterMode: RatingFilterMode = RatingFilterMode(rawValue: UserDefaults.standard.string(forKey: Keys.ratingFilterMode) ?? "") ?? .atLeast
    @State private var tagFilterExpanded       = UserDefaults.standard.object(forKey: Keys.tagFilterExpanded)       as? Bool ?? true
    @State private var locationFilterExpanded  = UserDefaults.standard.object(forKey: Keys.locationFilterExpanded)  as? Bool ?? true
    @State private var shotDateFilterExpanded  = UserDefaults.standard.object(forKey: Keys.shotDateFilterExpanded)  as? Bool ?? true
    @State private var dateFilterMode: DateFilterMode = DateFilterMode(rawValue: UserDefaults.standard.string(forKey: Keys.dateFilterMode) ?? "") ?? .off
    @State private var shotDateFrom: Date      = UserDefaults.standard.object(forKey: Keys.shotDateFrom) as? Date ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var shotDateTo: Date        = UserDefaults.standard.object(forKey: Keys.shotDateTo)   as? Date ?? Date()
    @State private var annualFilterDays: Int   = UserDefaults.standard.object(forKey: Keys.annualFilterDays) as? Int ?? 14
    @State private var colorLabelFilterExpanded = true
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
        .sheet(isPresented: $showSourceFolderManager, onDismiss: handleSourceManagerDismiss) {
            SourceFolderManagerSheet()
                .environment(sourceFolderStore)
        }
        .onAppear {
            columnVisibility = .all
            NotificationService.requestPermission()
            loadTabFiltersFromDefaults()
        }
        .task {
            // コピー先ブックマークをバックグラウンドで解決し、メインスレッドをブロックしない
            let dstTask = Task.detached { BookmarkStore.restore(Keys.dstPath) }
            let dst = await dstTask.value
            if dst != nil { dstURL = dst }
        }
        .background(WindowAccessor { window in
            window.setFrameAutosaveName("PixCurateMain")
        })
        .onChange(of: sourceFolderStore.onlineSpecs, initial: true) { _, newSpecs in
            guard !vm.isCollectionMode else { return }
            // 設定ダイアログ操作中は再読み込みせず、閉じたときにまとめて1回だけ実行する
            if showSourceFolderManager {
                sourcesNeedReload = true
                return
            }
            setupFiltersAndLoad(sources: newSpecs)
        }
        .onChange(of: dstURL) { _, newVal in
            if let url = newVal { BookmarkStore.save(url: url, key: Keys.dstPath) }
        }
        .onChange(of: sourceFolderStore.folders.map(\.id)) { _, ids in
            // 削除されたフォルダのタブ別フィルター記憶を破棄
            let idSet = Set(ids)
            tabFilters = tabFilters.filter { key, _ in
                if case .folder(let id) = key { return idSet.contains(id) }
                return true   // .all は常に保持
            }
            saveTabFiltersToDefaults()
            // 選択中のタブのフォルダが削除されたら「すべて」に戻す
            if case .folder(let id) = activeTab, !ids.contains(id) {
                activeTab = .all
            }
        }
        .onChange(of: sourceFolderStore.enabledFolders.map(\.id)) { _, ids in
            // 選択中のタブのフォルダが無効化されたら「すべて」に戻す
            if case .folder(let id) = activeTab, !ids.contains(id) {
                activeTab = .all
            }
        }
        .onChange(of: minRating) { _, newVal in
            UserDefaults.standard.set(newVal, forKey: Keys.minRating)
            if suppressPresetClear { return }
            vm.applyFilter(minRating: newVal, ratingMode: ratingFilterMode)
            clearActivePreset()
            persistActiveTabFilter()
        }
        .onChange(of: ratingFilterMode) { _, newVal in
            UserDefaults.standard.set(newVal.rawValue, forKey: Keys.ratingFilterMode)
            vm.ratingFilterMode = newVal   // バックグラウンドTaskの内部applyFilterにも反映
            if suppressPresetClear { return }
            vm.applyFilter(minRating: minRating, ratingMode: newVal)
            clearActivePreset()
            persistActiveTabFilter()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rescanRequested)) { _ in
            let specs = sourceFolderStore.onlineSpecs
            if !specs.isEmpty { vm.rescan(sources: specs, minRating: minRating) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rebuildRequested)) { _ in
            if !sourceFolderStore.folders.isEmpty { showRebuildConfirm = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetWindowState)) { _ in
            resetWindowState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .photoRatingChanged)) { note in
            guard let url = note.userInfo?["url"] as? URL else { return }
            let rating = note.userInfo?["rating"] as? Int
            vm.updateRating(for: url, rating: rating)
        }
        .onReceive(NotificationCenter.default.publisher(for: .photoColorLabelChanged)) { note in
            guard let url = note.userInfo?["url"] as? URL else { return }
            let labelStr = note.userInfo?["colorLabel"] as? String
            let label = labelStr.flatMap { ColorLabel(rawValue: $0) }
            vm.updateColorLabel(for: url, colorLabel: label)
        }
        .onChange(of: displaySettings.viewMode) { _, newMode in
            resizeWindowForMode(newMode)
        }
        .alert("エクスポートの確認", isPresented: Binding<Bool>(
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
        .alert("コレクション名の変更", isPresented: Binding<Bool>(
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
                vm.rebuildDB(sources: sourceFolderStore.onlineSpecs, minRating: minRating)
            }
        } message: {
            Text("DBを全削除してすべてのファイルを再スキャンします。件数が多い場合は時間がかかります。")
        }
        .alert("コレクションを削除", isPresented: Binding<Bool>(
            get: { deleteConfirmCollection != nil },
            set: { if !$0 { deleteConfirmCollection = nil } }
        )) {
            Button("キャンセル", role: .cancel) { deleteConfirmCollection = nil }
            Button("削除", role: .destructive) {
                if let col = deleteConfirmCollection {
                    if activeCollection?.id == col.id {
                        activeCollection = nil
                        vm.exitCollectionMode(sources: sourceFolderStore.onlineSpecs, minRating: minRating)
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
        .alert("プリセットを削除", isPresented: Binding<Bool>(
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
                        // コピー元フォルダ（複数設定）
                        sourceFolderSummaryRow
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
                        HStack(spacing: 6) {
                            ForEach(FileTypeFilter.allCases, id: \.self) { t in
                                let selected = fileTypeFilter == t
                                Button {
                                    fileTypeFilter = t
                                    UserDefaults.standard.set(t.rawValue, forKey: Keys.fileTypeFilter)
                                    vm.fileTypeFilter = t
                                    vm.applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
                                    persistActiveTabFilter()
                                } label: {
                                    Text(t.shortLabel)
                                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
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
                        VStack(alignment: .leading, spacing: 4) {
                            StarPickerView(selection: $minRating)
                            if minRating > 0 {
                                ratingModeToggle
                            }
                        }
                        .padding(.vertical, 2)
                    } label: {
                        filterLabel("評価", icon: "star.fill", color: .yellow)
                    }
                    .listRowInsets(SidebarLayout.rowInsets)
                    .onChange(of: ratingFilterExpanded) { _, v in
                        UserDefaults.standard.set(v, forKey: Keys.ratingFilterExpanded)
                    }

                    // カラーラベル
                    colorLabelFilterSection

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
                                        .frame(width: 48)
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
                            vm.exitCollectionMode(sources: sourceFolderStore.onlineSpecs, minRating: minRating)
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

    // MARK: - Color label filter UI

    private var ratingModeToggle: some View {
        HStack(spacing: 6) {
            ratingModeButton(label: "以上", mode: .atLeast)
            ratingModeButton(label: "のみ", mode: .exactly)
            Spacer()
        }
    }

    private func ratingModeButton(label: String, mode: RatingFilterMode) -> some View {
        let isSelected = ratingFilterMode == mode
        return Button { ratingFilterMode = mode } label: {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var colorLabelFilterSection: some View {
        DisclosureGroup(isExpanded: $colorLabelFilterExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(ColorLabel.allCases, id: \.self) { label in
                        let isOn = selectedColorLabels.contains(label)
                        Button {
                            if isOn {
                                selectedColorLabels.remove(label)
                            } else {
                                selectedColorLabels.insert(label)
                            }
                            applyColorLabelFilter()
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(label.color)
                                .overlay(
                                    isOn ? AnyView(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(label.color, lineWidth: 2)
                                            .padding(-3)
                                    ) : AnyView(EmptyView())
                                )
                        }
                        .buttonStyle(.plain)
                        .help(label.localizedName + "（" + String(label.keyChar).uppercased() + "キー）")
                    }
                    Spacer()
                }
                .padding(.top, 4)
                .padding(.bottom, selectedColorLabels.isEmpty ? 4 : 2)

                if !selectedColorLabels.isEmpty {
                    Text(selectedColorLabels.map(\.localizedName).sorted().joined(separator: "・") + " で絞り込み中")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .padding(.bottom, 4)
                }
            }
        } label: {
            filterLabel("カラーラベル", icon: "circle.fill", color: .pink)
        }
        .listRowInsets(SidebarLayout.rowInsets)
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
        vm.applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
        if clearPreset { activePresetId = nil }
        persistActiveTabFilter()
    }

    private func applyLocationFilter(clearPreset: Bool = true) {
        vm.locationFilter = selectedLocationIds
        vm.applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
        if clearPreset { activePresetId = nil }
        persistActiveTabFilter()
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
        vm.applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
        persistActiveTabFilter()
    }

    private func applyXmpFilter(clearPreset: Bool = true) {
        vm.xmpSinceFilter = useXmpSince ? xmpSinceDate : nil
        vm.applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
        if clearPreset { activePresetId = nil }
        persistActiveTabFilter()
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

    private func applyColorLabelFilter() {
        vm.colorLabelFilter = selectedColorLabels
        vm.applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
        persistActiveTabFilter()
    }

    private func applyColorLabelToSelection(label: ColorLabel?) {
        let files = vm.filteredFiles.filter { selection.contains($0.id) }
        guard !files.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            for file in files {
                _ = XMPService.writeColorLabel(to: file.xmpURL, label: label)
            }
            let updates = files.map { $0.rawURL }
            await MainActor.run {
                for url in updates {
                    vm.updateColorLabel(for: url, colorLabel: label)
                }
            }
        }
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
                sources: [],
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


    private func gridSortLabel(_ col: ListColumn?) -> String {
        switch col {
        case nil:       return "ファイル名"
        case .shotDate: return "撮影日時"
        case .rating:   return "評価"
        case .location: return "撮影地"
        case .tags:     return "タグ"
        case .xmpDate:  return "XMP更新日"
        default:        return "ファイル名"
        }
    }

    // MARK: - コピー元フォルダ サマリー行

    private var sourceFolderSummaryRow: some View {
        Button { showSourceFolderManager = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    let total = sourceFolderStore.folders.count
                    let online = sourceFolderStore.onlineSpecs.count
                    if total == 0 {
                        Text("コピー元フォルダ")
                            .foregroundStyle(.secondary)
                        Text("未設定 — クリックして追加")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("コピー元: \(total)フォルダ")
                            .foregroundStyle(.primary)
                        if online < total {
                            Text("オフライン: \(total - online)フォルダ")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else {
                            Text("すべてオンライン")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - フィルター初期化＆ロード

    /// コピー元フォルダ設定ダイアログを閉じたとき、変更があれば1回だけ再読み込みする（案C：差分ロード）
    private func handleSourceManagerDismiss() {
        guard sourcesNeedReload else { return }
        sourcesNeedReload = false
        guard !vm.isCollectionMode else { return }

        let newSpecs = sourceFolderStore.onlineSpecs
        // 前回ロード済みに無い＝新たに有効化されたフォルダだけを抽出
        let previous = Set(vm.loadedSources)
        let newlyAdded = newSpecs.filter { !previous.contains($0) }

        applyFilterStateToVM()
        vm.loadIncremental(sources: newSpecs, newlyAdded: newlyAdded, minRating: minRating)
    }

    /// ContentView 側のフィルター状態を VM に反映（ロードはしない）
    private func applyFilterStateToVM() {
        vm.xmpSinceFilter = useXmpSince ? xmpSinceDate : nil
        vm.locationFilter = selectedLocationIds
        vm.filterGroups = filterGroups.map { Array($0.tagNames) }
        vm.fileTypeFilter = fileTypeFilter
        vm.ratingFilterMode = ratingFilterMode
        switch dateFilterMode {
        case .off:
            vm.annualFilterDays = nil; vm.shotDateFrom = nil; vm.shotDateTo = nil
        case .annual:
            vm.annualFilterDays = annualFilterDays; vm.shotDateFrom = nil; vm.shotDateTo = nil
        case .range:
            vm.annualFilterDays = nil; vm.shotDateFrom = shotDateFrom; vm.shotDateTo = shotDateTo
        }
    }

    private func setupFiltersAndLoad(sources: [SourceSpec]) {
        applyFilterStateToVM()
        vm.load(sources: sources, minRating: minRating)
    }

    // MARK: - タブごとフィルター（案C：スナップショット記憶・復元）

    /// 現在のフィルター条件をスナップショットとして取り出す
    private func captureFilterState() -> TabFilterState {
        TabFilterState(
            minRating: minRating,
            ratingFilterMode: ratingFilterMode,
            filterGroups: filterGroups,
            selectedColorLabels: selectedColorLabels,
            selectedLocationIds: selectedLocationIds,
            fileTypeFilter: fileTypeFilter,
            dateFilterMode: dateFilterMode,
            shotDateFrom: shotDateFrom,
            shotDateTo: shotDateTo,
            annualFilterDays: annualFilterDays,
            useXmpSince: useXmpSince,
            xmpSinceDate: xmpSinceDate,
            activePresetId: activePresetId
        )
    }

    /// スナップショットからフィルター条件を復元し、再適用する
    private func restoreFilterState(_ s: TabFilterState) {
        suppressPresetClear = true
        defer { DispatchQueue.main.async { suppressPresetClear = false } }
        minRating           = s.minRating
        ratingFilterMode    = s.ratingFilterMode
        filterGroups        = s.filterGroups
        selectedColorLabels = s.selectedColorLabels
        selectedLocationIds = s.selectedLocationIds
        fileTypeFilter      = s.fileTypeFilter
        dateFilterMode      = s.dateFilterMode
        shotDateFrom        = s.shotDateFrom
        shotDateTo          = s.shotDateTo
        annualFilterDays    = s.annualFilterDays
        useXmpSince         = s.useXmpSince
        xmpSinceDate        = s.xmpSinceDate
        activePresetId      = s.activePresetId
        pushFiltersToVMAndApply()
    }

    /// ContentView 側のフィルター状態を VM に反映して再フィルターを実行する
    private func pushFiltersToVMAndApply() {
        vm.xmpSinceFilter   = useXmpSince ? xmpSinceDate : nil
        vm.locationFilter   = selectedLocationIds
        vm.filterGroups     = filterGroups.map { Array($0.tagNames) }
        vm.fileTypeFilter   = fileTypeFilter
        vm.ratingFilterMode = ratingFilterMode
        vm.colorLabelFilter = selectedColorLabels
        switch dateFilterMode {
        case .off:
            vm.annualFilterDays = nil; vm.shotDateFrom = nil; vm.shotDateTo = nil
        case .annual:
            vm.annualFilterDays = annualFilterDays; vm.shotDateFrom = nil; vm.shotDateTo = nil
        case .range:
            vm.annualFilterDays = nil; vm.shotDateFrom = shotDateFrom; vm.shotDateTo = shotDateTo
        }
        vm.applyFilter(minRating: minRating, ratingMode: ratingFilterMode)
    }

    /// タブを切り替える。現在タブのフィルターを保存し、移動先タブのフィルターを復元する。
    /// 移動先に記憶がなければ現在のフィルターを引き継ぐ（初回訪問）。
    private func switchTab(to tab: SourceTab) {
        guard tab != activeTab else { return }
        tabFilters[activeTab] = captureFilterState()
        activeTab = tab
        if let saved = tabFilters[tab] {
            restoreFilterState(saved)
        } else {
            // 初回訪問：現在のフィルターを引き継ぎ、その内容をこのタブの記憶として確定
            tabFilters[tab] = captureFilterState()
        }
    }

    /// TabFilterState → FilterSpec（実際にフィルターに使う形へ変換）
    private func filterSpec(from s: TabFilterState) -> FilterSpec {
        FilterSpec(
            minRating: s.minRating,
            ratingMode: s.ratingFilterMode,
            fileTypeFilter: s.fileTypeFilter,
            colorLabelFilter: s.selectedColorLabels,
            filterGroups: s.filterGroups.map { Array($0.tagNames) },
            locationFilter: s.selectedLocationIds,
            annualFilterDays: s.dateFilterMode == .annual ? s.annualFilterDays : nil,
            shotDateFrom: s.dateFilterMode == .range ? s.shotDateFrom : nil,
            shotDateTo:   s.dateFilterMode == .range ? s.shotDateTo : nil,
            xmpSinceFilter: s.useXmpSince ? s.xmpSinceDate : nil
        )
    }

    /// 指定タブのフィルター状態（アクティブタブは現在の編集中状態を使う）
    private func filterState(for tab: SourceTab) -> TabFilterState {
        if tab == activeTab { return captureFilterState() }
        return tabFilters[tab] ?? captureFilterState()
    }

    /// 指定タブの対象ファイル（フィルター前。フォルダ接頭辞でスライス）
    private func folderFiles(for tab: SourceTab) -> [PhotoFile] {
        switch tab {
        case .all:
            return vm.allFiles
        case .folder(let id):
            guard let folder = sourceFolderStore.folders.first(where: { $0.id == id }),
                  let url = folder.resolvedURL else { return [] }
            let base = url.path.hasSuffix("/") ? url.path : url.path + "/"
            return vm.allFiles.filter { $0.rawURL.path.hasPrefix(base) }
        }
    }

    /// 指定タブの件数を、そのタブ自身のフィルター条件で正確に計算する
    private func tabCount(_ tab: SourceTab) -> Int {
        // アクティブタブは vm.filteredFiles に計算済みなので再計算を避ける
        if tab == activeTab { return filesForActiveTab.count }
        return vm.count(in: folderFiles(for: tab), spec: filterSpec(from: filterState(for: tab)))
    }

    /// ステータスバー左（絞り込み件数）。タブ表示中はアクティブタブ基準。
    private var statusFilteredCount: Int {
        isTabbedMode ? filesForActiveTab.count : vm.filteredFiles.count
    }

    /// ステータスバー右（総件数）。タブ表示中はアクティブタブのフォルダの総数。
    private var statusTotalCount: Int {
        isTabbedMode ? folderFiles(for: activeTab).count : vm.allFiles.count
    }

    // MARK: - タブ別フィルターの永続化（フォルダタブのみ。「すべて」は従来のグローバル設定で保持）

    /// アクティブタブのフィルターを記憶（フォルダタブはディスクにも保存）
    private func persistActiveTabFilter() {
        tabFilters[activeTab] = captureFilterState()
        saveTabFiltersToDefaults()
    }

    private func saveTabFiltersToDefaults() {
        var dict: [String: TabFilterDTO] = [:]
        for (tab, st) in tabFilters {
            if case .folder(let id) = tab { dict[id.uuidString] = TabFilterDTO(st) }
        }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Keys.tabFilters)
        }
    }

    private func loadTabFiltersFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Keys.tabFilters),
              let dict = try? JSONDecoder().decode([String: TabFilterDTO].self, from: data)
        else { return }
        for (key, dto) in dict {
            if let id = UUID(uuidString: key) { tabFilters[.folder(id)] = dto.state }
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
        let srcSpecs = sourceFolderStore.onlineSpecs
        if !srcSpecs.isEmpty, let dst = dstURL {
            Button {
                vm.runCopy(to: dst, keepStructure: keepStructure, sources: srcSpecs, dryRun: true)
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
                    vm.runCopy(to: dst, keepStructure: keepStructure, sources: srcSpecs, dryRun: false)
                }
            } message: {
                let srcNames = srcSpecs.map { $0.url.lastPathComponent }.joined(separator: ", ")
                Text("""
                現在表示されている画像がコピー対象となります。

                コピー元: \(srcSpecs.count)フォルダ（\(srcNames)）
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

    // MARK: - フォルダ別タブ

    /// タブ表示が有効か（フォルダ別設定 かつ コレクションモードでない かつ フォルダが1つ以上）
    private var isTabbedMode: Bool {
        displaySettings.thumbnailGrouping == .byFolder
            && !vm.isCollectionMode
            && !sourceFolderStore.enabledFolders.isEmpty
    }

    /// 指定フォルダ配下のファイルだけを返す
    private func files(inFolder folder: SourceFolder) -> [PhotoFile] {
        guard let url = folder.resolvedURL else { return [] }
        let base = url.path.hasSuffix("/") ? url.path : url.path + "/"
        return vm.filteredFiles.filter { $0.rawURL.path.hasPrefix(base) }
    }

    /// 現在アクティブなタブに対応するファイル
    private var filesForActiveTab: [PhotoFile] {
        guard isTabbedMode else { return vm.filteredFiles }
        switch activeTab {
        case .all:
            return vm.filteredFiles
        case .folder(let id):
            guard let folder = sourceFolderStore.folders.first(where: { $0.id == id }) else {
                return vm.filteredFiles
            }
            return files(inFolder: folder)
        }
    }

    @ViewBuilder
    private var folderTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                folderTabButton(title: "すべて", count: tabCount(.all), tab: .all, online: true)
                ForEach(sourceFolderStore.enabledFolders) { folder in
                    let name = URL(fileURLWithPath: folder.displayPath).lastPathComponent
                    folderTabButton(
                        title: name,
                        count: tabCount(.folder(folder.id)),
                        tab: .folder(folder.id),
                        online: folder.isOnline
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(.bar)
    }

    private func folderTabButton(title: String, count: Int, tab: SourceTab, online: Bool) -> some View {
        let isActive = activeTab == tab
        return Button {
            switchTab(to: tab)
        } label: {
            HStack(spacing: 5) {
                if tab != .all {
                    Circle()
                        .fill(online ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? Color.white.opacity(0.9) : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isActive ? Color.accentColor.opacity(0.65)
                                                : Color.secondary.opacity(0.18))
                    )
            }
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
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
                        Text("\(statusFilteredCount) / \(statusTotalCount) ファイル")
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
                    // グリッドモード時のみソートコントロールを表示
                    if displaySettings.viewMode == .grid && !vm.filteredFiles.isEmpty {
                        Divider().frame(height: 14)

                        Menu {
                            ForEach([
                                (ListColumn?.none,   "ファイル名"),
                                (.some(.shotDate),   "撮影日時"),
                                (.some(.rating),     "評価"),
                                (.some(.location),   "撮影地"),
                                (.some(.tags),       "タグ"),
                                (.some(.xmpDate),    "XMP更新日"),
                            ] as [(ListColumn?, String)], id: \.1) { col, label in
                                Button {
                                    vm.setSort(column: col, ascending: vm.listSortAscending,
                                               minRating: minRating, ratingMode: ratingFilterMode)
                                } label: {
                                    if vm.listSortColumn == col {
                                        Label(label, systemImage: "checkmark")
                                    } else {
                                        Text(label)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 10))
                                Text(gridSortLabel(vm.listSortColumn))
                                    .font(.caption)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .foregroundStyle(.primary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("並び順を変更")

                        Button {
                            vm.setSort(column: vm.listSortColumn,
                                       ascending: !vm.listSortAscending,
                                       minRating: minRating, ratingMode: ratingFilterMode)
                        } label: {
                            Image(systemName: vm.listSortAscending ? "arrow.up" : "arrow.down")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .help(vm.listSortAscending ? "昇順" : "降順")
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
                    if !sourceFolderStore.onlineSpecs.isEmpty, !vm.isLoading, !vm.isCollectionMode {
                        Button {
                            vm.rescan(sources: sourceFolderStore.onlineSpecs, minRating: minRating)
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
                            // タブ表示中はアクティブなタブ内のみ追加選択（他タブの選択は維持）
                            selection.formUnion(filesForActiveTab.map(\.id))
                        } label: {
                            Image(systemName: "square.stack.fill")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .help(isTabbedMode ? "このタブを全選択" : "全選択")

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
                                openWindow(id: "photo-viewer", value: PhotoViewerRequest(url: file.rawURL))
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

                // フォルダ別タブ
                if isTabbedMode {
                    folderTabBar
                    Divider()
                }

                FileListView(
                    files: filesForActiveTab,
                    totalCount: vm.allFiles.count,
                    selection: $selection,
                    sortColumn: vm.listSortColumn,
                    sortAscending: vm.listSortAscending,
                    onRateSelected: { applyRatingToSelection(rating: $0) },
                    onColorLabelSelected: { applyColorLabelToSelection(label: $0) },
                    onSort: { vm.toggleListSort(column: $0, minRating: minRating, ratingMode: ratingFilterMode) },
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
        Button { pick() } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
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
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

import SwiftUI
import UniformTypeIdentifiers

// MARK: - FileListView

struct FileListView: View {
    let files: [PhotoFile]
    let totalCount: Int
    @Binding var selection: Set<UUID>
    let sortColumn: ListColumn?
    let sortAscending: Bool
    let onRateSelected: (Int?) -> Void
    let onColorLabelSelected: (ColorLabel?) -> Void
    let onSort: (ListColumn?) -> Void
    // コレクション
    let collections: [PhotoCollection]
    let activeCollectionId: UUID?
    let onAddToCollection: (PhotoCollection, [PhotoFile]) -> Void
    let onCreateAndAdd: ([PhotoFile]) -> Void
    let onRemoveFromCollection: (([PhotoFile]) -> Void)?
    /// サムネイル再読み込み用トークン（変化でセルの .task を再実行）
    var thumbnailRefreshToken: Int = 0

    @Environment(DisplaySettings.self) var settings
    @Environment(\.openWindow) var openWindow
    @State private var exifTarget: PhotoFile?
    @State private var gridColumnCount: Int = 4   // 矢印キー移動用・幅測定で随時更新

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: settings.thumbSize.width,
                            maximum: settings.thumbSize.width + 20),
                  spacing: settings.thumbSize.spacing)]
    }

    var body: some View {
        if files.isEmpty {
            if totalCount > 0 {
                ContentUnavailableView(
                    "フィルター条件に一致なし",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("「全」を選択するか★フィルターを下げてください（\(totalCount)件あります）")
                )
            } else {
                ContentUnavailableView(
                    "ファイルなし",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("コピー元フォルダを選択してください")
                )
            }
        } else if settings.viewMode == .grid {
            gridView
        } else {
            listView
        }
    }

    // MARK: - Grid

    private var gridView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: settings.thumbSize.spacing) {
                    ForEach(files) { file in
                        PhotoCell(file: file, isSelected: selection.contains(file.id),
                                  refreshToken: thumbnailRefreshToken)
                            .id(file.id)
                            .onTapGesture(count: 2) {
                                selection = [file.id]
                                openViewer(file, nil)
                            }
                            .onTapGesture {
                                handleTap(file)
                            }
                            .contextMenu { cellContextMenu(for: file) }
                    }
                }
                .padding(12)
            }
            .applyGridBackground(settings.gridBackground)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { updateGridColumnCount(width: geo.size.width) }
                    .onChange(of: geo.size.width) { _, w in updateGridColumnCount(width: w) }
            })
            .onTapGesture { selection.removeAll() }
            .focusable()
            .onKeyPress(phases: .down) { handleKeyPress($0) }
            .onChange(of: selection) { _, newSel in
                // キーボード移動時のみスクロール追従（単一選択かつ矢印操作の結果）
                if newSel.count == 1, let id = newSel.first {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .sheet(item: $exifTarget) { ExifInfoSheet(file: $0) }
    }

    private func updateGridColumnCount(width: CGFloat) {
        let spacing = settings.thumbSize.spacing
        let minWidth = settings.thumbSize.width
        // padding(12) が両端にあるので内側幅 = width - 24
        let inner = max(minWidth, width - 24)
        gridColumnCount = max(1, Int((inner + spacing) / (minWidth + spacing)))
    }

    // MARK: - List
    // ヘッダーは ScrollView 外の VStack に置く。
    // 行もヘッダーも同じ .padding(.horizontal, rowHPad) + 同一 HStack 構造 → 完全一致

    // 表示中の列幅合計からコンテンツの最小幅を計算
    private var listContentMinWidth: CGFloat {
        let colsWidth = ListColumn.allCases
            .filter { settings.listColumns.contains($0) }
            .reduce(0) { $0 + $1.columnWidth }
        return ListLayout.rowHPad * 2 + ListLayout.thumbWidth + ListLayout.thumbGap + 150 + colsWidth
    }

    private var listView: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(files) { file in
                        PhotoListRow(file: file, isSelected: selection.contains(file.id),
                                     refreshToken: thumbnailRefreshToken)
                            .padding(.horizontal, ListLayout.rowHPad)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                openViewer(file, nil)
                            }
                            .onTapGesture { handleTap(file) }
                            .contextMenu { cellContextMenu(for: file) }
                        Divider()
                            .padding(.leading, ListLayout.rowHPad + ListLayout.rowLeading)
                    }
                } header: {
                    VStack(spacing: 0) {
                        listHeaderRow
                        Divider()
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .frame(minWidth: listContentMinWidth)
        }
        .applyGridBackground(settings.gridBackground)
        .onTapGesture { selection.removeAll() }
        .focusable()
        .onKeyPress(phases: .down) { handleKeyPress($0) }
        .sheet(item: $exifTarget) { ExifInfoSheet(file: $0) }
    }

    private var listHeaderRow: some View {
        // 行の HStack 構造と完全に同じ：
        //   ① Color.clear(thumbWidth) + ② Color.clear(thumbGap) + ③ filename(flex) + ④ 各列(固定幅)
        // 外側 padding も行と同じ rowHPad
        HStack(spacing: 0) {
            Text("画像")                                        // ① thumb 幅
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: ListLayout.thumbWidth, alignment: .center)
            Color.clear.frame(width: ListLayout.thumbGap)     // ② gap 幅

            sortHeaderButton(label: "ファイル名", column: nil)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)

            ForEach(ListColumn.allCases.filter { settings.listColumns.contains($0) }) { col in
                Group {
                    if col.needsEXIF {
                        Text(col.label).font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        sortHeaderButton(label: col.label, column: col)
                    }
                }
                .frame(width: col.columnWidth, alignment: .leading)
            }
        }
        .padding(.horizontal, ListLayout.rowHPad)
        .frame(height: 26)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func sortHeaderButton(label: String, column: ListColumn?) -> some View {
        let active = sortColumn == column
        return HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
            if active {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .contentShape(Rectangle())
        .onTapGesture { onSort(column) }
    }

    // MARK: - 拡大表示

    /// size が nil の場合は表示設定のデフォルトサイズで開く
    private func openViewer(_ file: PhotoFile, _ size: DisplaySettings.ViewerSize?) {
        openWindow(id: "photo-viewer", value: PhotoViewerRequest(url: file.rawURL, size: size))
    }

    // MARK: - Shared context menu

    @ViewBuilder
    private func cellContextMenu(for file: PhotoFile) -> some View {
        Button { exifTarget = file } label: {
            Label("情報を表示", systemImage: "info.circle")
        }
        Button { openViewer(file, .normal) } label: {
            Label("通常サイズで表示", systemImage: "macwindow")
        }
        Button { openViewer(file, .fit) } label: {
            Label("画面に合わせて表示", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        Button { openViewer(file, .pixel) } label: {
            Label("ピクセル等倍で表示", systemImage: "1.magnifyingglass")
        }
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([file.rawURL])
        } label: {
            Label("Finderで表示", systemImage: "folder")
        }
        Menu {
            openWithMenuItems(for: file)
        } label: {
            Label("開く", systemImage: "square.and.arrow.up.on.square")
        }
        Divider()
        Menu("評価を設定") {
            Button("★★★★★  5") { onRateSelected(5) }
            Button("★★★★    4") { onRateSelected(4) }
            Button("★★★      3") { onRateSelected(3) }
            Button("★★        2") { onRateSelected(2) }
            Button("★          1") { onRateSelected(1) }
            Divider()
            Button("評価を解除  0") { onRateSelected(nil) }
        }
        Menu("カラーラベルを設定") {
            ForEach(ColorLabel.allCases, id: \.self) { label in
                Button {
                    onColorLabelSelected(label)
                } label: {
                    Label(label.localizedName + "  \(label.keyChar.uppercased())",
                          systemImage: "bookmark.fill")
                }
            }
            Divider()
            Button("解除  X") { onColorLabelSelected(nil) }
        }
        Divider()
        // コレクション操作
        let targets = contextTargets(for: file)
        Menu("コレクションに追加") {
            collectionMenuItems(parent: nil, targets: targets)
            if !collections.isEmpty { Divider() }
            Button("新規コレクションを作成して追加…") { onCreateAndAdd(targets) }
        }
        if activeCollectionId != nil, let remove = onRemoveFromCollection {
            Button(role: .destructive) { remove(targets) } label: {
                Label("このコレクションから削除", systemImage: "minus.circle")
            }
        }
    }

    /// コレクション階層をネストしたサブメニューとして表示（グループ=サブメニュー、葉=追加ボタン）
    /// 再帰のため AnyView で型を消去する
    private func collectionMenuItems(parent: UUID?, targets: [PhotoFile]) -> AnyView {
        let children = collections
            .filter { $0.parentId == parent }
            .sorted { $0.createdAt < $1.createdAt }
        return AnyView(
            ForEach(children) { col in
                if collections.contains(where: { $0.parentId == col.id }) {
                    Menu(col.name) { collectionMenuItems(parent: col.id, targets: targets) }
                } else {
                    Button(col.name) { onAddToCollection(col, targets) }
                }
            }
        )
    }

    // 右クリックされたファイルが選択中なら選択全体、そうでなければそのファイルのみ
    private func contextTargets(for file: PhotoFile) -> [PhotoFile] {
        if selection.contains(file.id) {
            return files.filter { selection.contains($0.id) }
        }
        return [file]
    }

    // MARK: - 「開く」メニュー（現像アプリ等で起動）

    /// 右クリックされたファイル（選択中なら選択全体）を対象に、起動アプリ候補を出す
    private func openWithMenuItems(for file: PhotoFile) -> AnyView {
        let urls = contextTargets(for: file).map(\.rawURL)
        let primary = urls.first ?? file.rawURL
        // 現像系アプリ（Photoshop/Bridge/Lightroom 等）を優先表示。
        // ※「Camera Raw」は単体アプリではないため、Photoshop で開くと Camera Raw が起動する。
        let developApps = developApplications()
        // 型登録から自動検出した対応アプリ（現像アプリと重複するものは除く）
        let developPaths = Set(developApps.map { $0.standardizedFileURL.path })
        let otherApps = NSWorkspace.shared.urlsForApplications(toOpen: primary)
            .filter { !developPaths.contains($0.standardizedFileURL.path) }
        return AnyView(
            Group {
                if !developApps.isEmpty {
                    ForEach(developApps, id: \.self) { appURL in
                        Button(appDisplayName(appURL)) { openFiles(urls, with: appURL) }
                    }
                    Divider()
                }
                Button("デフォルトアプリで開く") { openFiles(urls, with: nil) }
                if !otherApps.isEmpty {
                    Menu("対応アプリで開く") {
                        ForEach(otherApps, id: \.self) { appURL in
                            Button(appDisplayName(appURL)) { openFiles(urls, with: appURL) }
                        }
                    }
                }
                Divider()
                Button("ほかのアプリを選択…") { chooseApplicationAndOpen(urls) }
            }
        )
    }

    /// インストール済みの現像系アプリを名前で探す（型登録に依存せず検出する）。
    /// Adobe 製品は「/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app」のように
    /// 1 階層下に入るため、サブフォルダも 1 段だけ走査する。
    private func developApplications() -> [URL] {
        let keywords = ["photoshop", "bridge", "lightroom", "capture one", "dxo",
                        "affinity photo", "raw power", "rawtherapee", "darktable",
                        "luminar", "silkypix", "iridient", "graphicconverter"]
        func isDevelopApp(_ name: String) -> Bool {
            let lower = name.lowercased()
            return keywords.contains { lower.contains($0) }
        }
        let fm = FileManager.default
        let roots = ["/Applications",
                     (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        var found: [String: URL] = [:]   // path -> url（重複排除）
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries {
                let path = (root as NSString).appendingPathComponent(entry)
                if entry.hasSuffix(".app") {
                    if isDevelopApp(entry) { found[path] = URL(fileURLWithPath: path) }
                } else if let subs = try? fm.contentsOfDirectory(atPath: path) {
                    for sub in subs where sub.hasSuffix(".app") && isDevelopApp(sub) {
                        let p = (path as NSString).appendingPathComponent(sub)
                        found[p] = URL(fileURLWithPath: p)
                    }
                }
            }
        }
        return found.values.sorted {
            appDisplayName($0).localizedCaseInsensitiveCompare(appDisplayName($1)) == .orderedAscending
        }
    }

    private func appDisplayName(_ appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// ファイル群を指定アプリ（nil ならデフォルト）で開く
    private func openFiles(_ urls: [URL], with appURL: URL?) {
        guard !urls.isEmpty else { return }
        let config = NSWorkspace.OpenConfiguration()
        if let appURL {
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
        } else {
            for url in urls { NSWorkspace.shared.open(url) }
        }
    }

    /// アプリ選択パネルを出して、選んだアプリで開く
    private func chooseApplicationAndOpen(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "起動するアプリケーションを選択"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let appURL = panel.url {
            openFiles(urls, with: appURL)
        }
    }

    // MARK: - Key press

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // 数字キー 0〜5: 評価設定
        if !selection.isEmpty,
           let ch = press.characters.first,
           let digit = ch.wholeNumberValue,
           (0...5).contains(digit) {
            onRateSelected(digit == 0 ? nil : digit)
            return .handled
        }

        // カラーラベルキー r/y/g/b/p/x（選択中かつ修飾キーなし）
        if !selection.isEmpty, press.modifiers.isEmpty,
           let ch = press.characters.first {
            switch ch {
            case "r": onColorLabelSelected(.red);    return .handled
            case "y": onColorLabelSelected(.yellow); return .handled
            case "g": onColorLabelSelected(.green);  return .handled
            case "b": onColorLabelSelected(.blue);   return .handled
            case "p": onColorLabelSelected(.purple); return .handled
            case "x": onColorLabelSelected(nil);     return .handled
            default: break
            }
        }

        // 矢印キー: グリッドモードのみ
        if settings.viewMode == .grid {
            switch press.key {
            case .leftArrow:  return moveGridSelection(by: -1)
            case .rightArrow: return moveGridSelection(by: +1)
            case .upArrow:    return moveGridSelection(by: -gridColumnCount)
            case .downArrow:  return moveGridSelection(by: +gridColumnCount)
            default: break
            }
        }

        return .ignored
    }

    private func moveGridSelection(by delta: Int) -> KeyPress.Result {
        guard !files.isEmpty else { return .ignored }

        // 未選択なら先頭 or 末尾を選択
        guard let currentId = selection.first,
              let currentIdx = files.firstIndex(where: { $0.id == currentId }) else {
            selection = [delta >= 0 ? files.first!.id : files.last!.id]
            return .handled
        }

        let newIdx = max(0, min(files.count - 1, currentIdx + delta))
        guard newIdx != currentIdx else { return .handled }
        selection = [files[newIdx].id]
        return .handled
    }

    // MARK: - Tap handling (grid only)

    private func handleTap(_ file: PhotoFile) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(file.id) {
                selection.remove(file.id)
            } else {
                selection.insert(file.id)
            }
        } else if NSEvent.modifierFlags.contains(.shift), let anchor = selection.first,
                  let anchorIdx = files.firstIndex(where: { $0.id == anchor }),
                  let targetIdx = files.firstIndex(where: { $0.id == file.id }) {
            let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
            selection = Set(files[range].map(\.id))
        } else {
            selection = [file.id]
        }
    }
}

// MARK: - Background color scheme helper

private extension View {
    @ViewBuilder
    func applyGridBackground(_ bg: DisplaySettings.GridBackground) -> some View {
        switch bg {
        case .system:
            self
        case .white:
            self.background(Color.white).colorScheme(.light)
        case .black:
            self.background(Color.black).colorScheme(.dark)
        }
    }
}

// MARK: - PhotoCell

struct PhotoCell: View {
    let file: PhotoFile
    let isSelected: Bool
    /// 値が変わると .task が再実行され、サムネイルを再読み込みする（更新後JPEG反映用）
    var refreshToken: Int = 0

    @State private var thumbnail: NSImage?
    @State private var thumbnailFailed = false
    @Environment(LocationStore.self) var locationStore
    @Environment(DisplaySettings.self) var settings

    var body: some View {
        let w = settings.thumbSize.width
        let h = settings.thumbSize.height
        let fontSize = settings.badgeFont.size

        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: w, height: h)

                if file.isOffline {
                    OfflinePlaceholder(url: file.rawURL, size: CGSize(width: w, height: h))
                } else if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if thumbnailFailed {
                    Image(systemName: "photo")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 0)
                        .frame(width: w, height: h)
                }

                // Overlay badges
                VStack {
                    HStack {
                        if file.isJpeg {
                            Text("JPEG")
                                .font(.system(size: fontSize - 1, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.15, green: 0.6, blue: 0.4).opacity(0.88))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .padding(5)
                        } else if settings.showLocation, let locId = file.locationId {
                            let locName = locationStore.path(of: locId).last?.name ?? ""
                            HStack(spacing: 2) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: fontSize - 1))
                                Text(locName)
                                    .font(.system(size: fontSize, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(5)
                        }
                        Spacer()
                        // カラーラベルアイコン（右上）
                        if let label = file.colorLabel {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: fontSize + 3, weight: .bold))
                                .foregroundStyle(label.color)
                                .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
                                .padding(.top, 3)
                                .padding(.trailing, 4)
                        }
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        if settings.showTags, !file.tags.isEmpty {
                            Text(file.tags.joined(separator: " "))
                                .font(.system(size: fontSize, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .padding(5)
                        }
                        Spacer()
                        if settings.showRating, let r = file.rating {
                            Text(String(repeating: "★", count: r))
                                .font(.system(size: fontSize + 1, weight: .bold))
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(5)
                        }
                    }
                }
                .frame(width: w, height: h)
            }
            .frame(width: w, height: h)

            if settings.showFilename {
                Text(file.filename)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: w)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }

            if settings.showShotDate, let date = file.shotDate {
                Text(shotDateString(date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: w)
            }
        }
        .task(id: "\(refreshToken)\u{1}\(file.rawURL.path)") {
            guard !file.isOffline else { return }
            thumbnailFailed = false
            let img = await ThumbnailService.thumbnail(for: file.rawURL)
            thumbnail = img
            thumbnailFailed = (img == nil)
        }
    }

    private func shotDateString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let y = c.year, let mo = c.month, let d = c.day,
              let h = c.hour, let mi = c.minute else { return "" }
        return String(format: "%04d/%02d/%02d %02d:%02d", y, mo, d, h, mi)
    }
}

// MARK: - OfflinePlaceholder

struct OfflinePlaceholder: View {
    let url: URL
    let size: CGSize

    private var volumeName: String {
        url.volumeName ?? url.deletingLastPathComponent().path
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: min(size.width, size.height) * 0.28))
                .foregroundStyle(.secondary)
            Text(volumeName)
                .font(.system(size: max(8, min(size.width * 0.09, 11))))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - StarBadgeView（他のViewから参照用に残す）

struct StarBadgeView: View {
    let rating: Int?

    var body: some View {
        if let r = rating {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= r ? "star.fill" : "star")
                        .foregroundStyle(i <= r ? Color.yellow : Color.secondary.opacity(0.3))
                        .font(.system(size: 10))
                }
            }
        } else {
            Text("—")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

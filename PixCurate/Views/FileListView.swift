import SwiftUI

// MARK: - FileListView

struct FileListView: View {
    let files: [PhotoFile]
    let totalCount: Int
    @Binding var selection: Set<UUID>
    let sortColumn: ListColumn?
    let sortAscending: Bool
    let onRateSelected: (Int?) -> Void
    let onSort: (ListColumn?) -> Void
    // コレクション
    let collections: [PhotoCollection]
    let activeCollectionId: UUID?
    let onAddToCollection: (PhotoCollection, [PhotoFile]) -> Void
    let onCreateAndAdd: ([PhotoFile]) -> Void
    let onRemoveFromCollection: (([PhotoFile]) -> Void)?

    @Environment(DisplaySettings.self) var settings
    @Environment(\.openWindow) var openWindow
    @State private var exifTarget: PhotoFile?

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
        ScrollView {
            LazyVGrid(columns: columns, spacing: settings.thumbSize.spacing) {
                ForEach(files) { file in
                    PhotoCell(file: file, isSelected: selection.contains(file.id))
                        .onTapGesture(count: 2) {
                            openWindow(id: "photo-viewer", value: file.rawURL)
                        }
                        .onTapGesture {
                            handleTap(file)
                        }
                        .contextMenu { cellContextMenu(for: file) }
                }
            }
            .padding(12)
        }
        .onTapGesture { selection.removeAll() }
        .focusable()
        .onKeyPress(phases: .down) { handleKeyPress($0) }
        .sheet(item: $exifTarget) { ExifInfoSheet(file: $0) }
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
                        PhotoListRow(file: file, isSelected: selection.contains(file.id))
                            .padding(.horizontal, ListLayout.rowHPad)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                openWindow(id: "photo-viewer", value: file.rawURL)
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
            Color.clear.frame(width: ListLayout.thumbWidth)   // ① thumb 幅
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

    // MARK: - Shared context menu

    @ViewBuilder
    private func cellContextMenu(for file: PhotoFile) -> some View {
        Button { exifTarget = file } label: {
            Label("情報を表示", systemImage: "info.circle")
        }
        Button { openWindow(id: "photo-viewer", value: file.rawURL) } label: {
            Label("大きく表示", systemImage: "arrow.up.left.and.arrow.down.right")
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
        Divider()
        // コレクション操作
        let targets = contextTargets(for: file)
        Menu("コレクションに追加") {
            ForEach(collections) { col in
                Button(col.name) { onAddToCollection(col, targets) }
            }
            if !collections.isEmpty { Divider() }
            Button("新規コレクションを作成して追加…") { onCreateAndAdd(targets) }
        }
        if activeCollectionId != nil, let remove = onRemoveFromCollection {
            Button(role: .destructive) { remove(targets) } label: {
                Label("このコレクションから削除", systemImage: "minus.circle")
            }
        }
    }

    // 右クリックされたファイルが選択中なら選択全体、そうでなければそのファイルのみ
    private func contextTargets(for file: PhotoFile) -> [PhotoFile] {
        if selection.contains(file.id) {
            return files.filter { selection.contains($0.id) }
        }
        return [file]
    }

    // MARK: - Key press

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard !selection.isEmpty,
              let ch = press.characters.first,
              let digit = ch.wholeNumberValue,
              (0...5).contains(digit) else { return .ignored }
        onRateSelected(digit == 0 ? nil : digit)
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

// MARK: - PhotoCell

struct PhotoCell: View {
    let file: PhotoFile
    let isSelected: Bool

    @State private var thumbnail: NSImage?
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
                        .aspectRatio(contentMode: .fill)
                        .frame(width: w, height: h)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: w, height: h)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.15))
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
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        if settings.showTags, !file.tags.isEmpty {
                            Text(file.tags.prefix(2).joined(separator: " "))
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
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: w)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }

            if settings.showShotDate, let date = file.shotDate {
                Text(shotDateString(date))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: w)
            }
        }
        .task(id: file.rawURL) {
            guard !file.isOffline else { return }
            thumbnail = await ThumbnailService.thumbnail(for: file.rawURL)
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

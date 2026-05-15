import SwiftUI

// MARK: - FileListView

struct FileListView: View {
    let files: [PhotoFile]
    let totalCount: Int
    @Binding var selection: Set<UUID>
    @Environment(DisplaySettings.self) var settings
    @Environment(\.openWindow) var openWindow

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
        } else {
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
                    }
                }
                .padding(12)
            }
            .onTapGesture { selection.removeAll() }
        }
    }

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

                if let thumb = thumbnail {
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
                        if settings.showLocation, let locId = file.locationId {
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
            thumbnail = await ThumbnailService.thumbnail(for: file.rawURL,
                                                         maxPixel: settings.thumbSize.maxPixel)
        }
        .onChange(of: settings.thumbSize) { _, _ in
            Task {
                thumbnail = await ThumbnailService.thumbnail(for: file.rawURL,
                                                              maxPixel: settings.thumbSize.maxPixel)
            }
        }
    }

    private func shotDateString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let y = c.year, let mo = c.month, let d = c.day,
              let h = c.hour, let mi = c.minute else { return "" }
        return String(format: "%04d/%02d/%02d %02d:%02d", y, mo, d, h, mi)
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

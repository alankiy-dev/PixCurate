import SwiftUI

struct PhotoListRow: View {
    let file: PhotoFile
    let isSelected: Bool

    @State private var thumbnail: NSImage?
    @State private var exifInfo: EXIFInfo?
    @Environment(DisplaySettings.self) var settings
    @Environment(LocationStore.self) var locationStore

    var body: some View {
        // 外側の padding は呼び出し元 (.padding(.horizontal, ListLayout.rowHPad)) で付与
        HStack(spacing: 0) {
            // ① サムネイル（固定幅）
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                if file.isOffline {
                    OfflinePlaceholder(url: file.rawURL,
                                       size: CGSize(width: ListLayout.thumbWidth,
                                                    height: ListLayout.thumbHeight))
                } else if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: ListLayout.thumbWidth, height: ListLayout.thumbHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    ProgressView().scaleEffect(0.5)
                }
            }
            .frame(width: ListLayout.thumbWidth, height: ListLayout.thumbHeight)

            // ② サムネイルとファイル名の間のギャップ（明示的 frame）
            Color.clear.frame(width: ListLayout.thumbGap)

            // ③ ファイル名（可変幅）
            Text(file.filename)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)

            // ④ 各列（固定幅）
            ForEach(ListColumn.allCases.filter { settings.listColumns.contains($0) }) { col in
                columnView(col)
                    .frame(width: col.columnWidth, alignment: .leading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: ListLayout.thumbHeight + ListLayout.rowVPad * 2)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .task(id: file.rawURL) {
            guard !file.isOffline else { return }
            async let thumb = ThumbnailService.thumbnail(
                for: file.rawURL, maxPixel: Int(ListLayout.thumbWidth * 2))
            thumbnail = await thumb

            if settings.listColumns.contains(where: \.needsEXIF) {
                let url = file.rawURL
                exifInfo = await Task.detached { EXIFService.readEXIFInfo(url: url) }.value
            }
        }
        .onChange(of: settings.listColumns) { _, _ in
            if exifInfo == nil && settings.listColumns.contains(where: \.needsEXIF) {
                let url = file.rawURL
                Task {
                    exifInfo = await Task.detached { EXIFService.readEXIFInfo(url: url) }.value
                }
            }
        }
    }

    // MARK: - Column cells

    @ViewBuilder
    private func columnView(_ col: ListColumn) -> some View {
        switch col {
        case .shotDate:
            Text(file.shotDate.map(formatDate) ?? "")
        case .rating:
            if let r = file.rating {
                Text(String(repeating: "★", count: r)).foregroundStyle(.yellow)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        case .location:
            Text(file.locationId.map { locationStore.path(of: $0).last?.name ?? "" } ?? "")
                .lineLimit(1)
        case .tags:
            Text(file.tags.prefix(2).joined(separator: "  ")).lineLimit(1)
        case .xmpDate:
            Text(file.xmpModifiedAt.map(formatDate) ?? "")
        case .camera:
            Text(exifInfo.map { [$0.cameraMake, $0.cameraModel].compactMap { $0 }.joined(separator: " ") } ?? "")
                .lineLimit(1)
        case .lens:
            Text(exifInfo?.lensModel ?? "").lineLimit(1)
        case .focalLength:
            Text(exifInfo?.focalLength.map { "\(Int($0))mm" } ?? "")
        case .aperture:
            Text(exifInfo?.aperture.map { String(format: "f/%.1f", $0) } ?? "")
        case .shutterSpeed:
            Text(exifInfo?.shutterSpeed.map { shutterString($0) } ?? "")
        case .iso:
            Text(exifInfo?.iso.map { "ISO\($0)" } ?? "")
        case .resolution:
            Text(exifInfo.flatMap { e in
                (e.imageWidth.flatMap { w in e.imageHeight.map { h in "\(w)×\(h)" } })
            } ?? "")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let y = c.year, let mo = c.month, let d = c.day,
              let h = c.hour, let mi = c.minute else { return "" }
        return String(format: "%04d/%02d/%02d %02d:%02d", y, mo, d, h, mi)
    }

    private func shutterString(_ seconds: Double) -> String {
        if seconds >= 1 { return String(format: "%.1f秒", seconds) }
        return "1/\(Int((1.0 / seconds).rounded()))秒"
    }
}

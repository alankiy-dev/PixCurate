import SwiftUI

/// 右パネルの「情報」タブ。選択中の1枚について、ファイルプロパティと Exif を表示する。
struct MetadataPanelView: View {
    let file: PhotoFile

    @State private var info: EXIFInfo?
    @State private var fileSize: Int64?
    @State private var copiedLabel: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                section("ファイル") {
                    row("ファイル名", file.filename)
                    if let d = file.shotDate { row("撮影日時", shotDateString(d)) }
                    if let sz = fileSize { row("サイズ", byteString(sz)) }
                    if let w = info?.imageWidth, let h = info?.imageHeight {
                        row("寸法", "\(w) × \(h) px")
                    }
                    row("評価", file.rating.map { String(repeating: "★", count: $0) } ?? "—")
                    if let lp = file.locationPath {
                        let parts = [lp.province, lp.city, lp.sublocation].compactMap { $0 }.filter { !$0.isEmpty }
                        if !parts.isEmpty { row("撮影地", parts.joined(separator: " / ")) }
                    }
                    if !file.tags.isEmpty { row("タグ", file.tags.joined(separator: ", ")) }
                }

                section("カメラ (Exif)") {
                    if let make = info?.cameraMake, let model = info?.cameraModel {
                        row("カメラ", "\(make) \(model)")
                    } else if let model = info?.cameraModel {
                        row("カメラ", model)
                    }
                    if let lens = info?.lensModel { row("レンズ", lens) }
                    if let fl = info?.focalLength { row("焦点距離", "\(Int(fl)) mm") }
                    if let f = info?.aperture { row("絞り", String(format: "f/%.1f", f)) }
                    if let ss = info?.shutterSpeed { row("シャッター", shutterString(ss)) }
                    if let iso = info?.iso { row("ISO", "\(iso)") }
                    if info == nil {
                        HStack { ProgressView().scaleEffect(0.6); Text("読み込み中…").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: file.rawURL) {
            info = nil
            fileSize = nil
            let url = file.rawURL
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let n = attrs[.size] as? NSNumber {
                fileSize = n.int64Value
            }
            info = await Task.detached { EXIFService.readEXIFInfo(url: url) }.value
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.primary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(value, forType: .string)
                copiedLabel = label
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if copiedLabel == label { copiedLabel = nil }
                }
            } label: {
                Image(systemName: copiedLabel == label ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(copiedLabel == label ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("「\(label)」をコピー")
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func shutterString(_ ss: Double) -> String {
        ss >= 1 ? String(format: "%.1f秒", ss) : "1/\(Int((1.0 / ss).rounded()))秒"
    }

    private func shotDateString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let y = c.year, let mo = c.month, let d = c.day, let h = c.hour, let mi = c.minute
        else { return "" }
        return String(format: "%04d/%02d/%02d %02d:%02d", y, mo, d, h, mi)
    }
}

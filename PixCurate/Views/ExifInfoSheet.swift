import SwiftUI

struct ExifInfoSheet: View {
    let file: PhotoFile
    @State private var info: EXIFInfo?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(file.filename)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("閉じる") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            if let info {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        if let make = info.cameraMake, let model = info.cameraModel {
                            row("カメラ", value: "\(make) \(model)")
                        } else if let model = info.cameraModel {
                            row("カメラ", value: model)
                        }
                        if let lens = info.lensModel {
                            row("レンズ", value: lens)
                        }
                        if let fl = info.focalLength {
                            row("焦点距離", value: "\(Int(fl)) mm")
                        }
                        if let f = info.aperture {
                            row("絞り", value: String(format: "f/%.1f", f))
                        }
                        if let ss = info.shutterSpeed {
                            row("シャッタースピード", value: shutterString(ss))
                        }
                        if let iso = info.iso {
                            row("ISO", value: "\(iso)")
                        }
                        if let date = info.shotDate {
                            row("撮影日時", value: DateFormatter.localizedString(
                                from: date, dateStyle: .medium, timeStyle: .medium))
                        }
                        if let w = info.imageWidth, let h = info.imageHeight {
                            row("解像度", value: "\(w) × \(h) px")
                        }
                    }
                    .padding()
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 400, minHeight: 200)
        .task {
            let url = file.rawURL
            info = await Task.detached { EXIFService.readEXIFInfo(url: url) }.value
        }
    }

    @ViewBuilder
    private func row(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .gridColumnAlignment(.leading)
        }
    }

    private func shutterString(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.1f秒", seconds)
        } else {
            let denom = Int((1.0 / seconds).rounded())
            return "1/\(denom)秒"
        }
    }
}

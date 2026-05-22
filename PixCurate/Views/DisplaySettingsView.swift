import SwiftUI

struct DisplaySettingsView: View {
    @Environment(DisplaySettings.self) var settings

    var body: some View {
        @Bindable var s = settings
        VStack(alignment: .leading, spacing: 16) {
            Text("表示設定").font(.headline)

            Divider()

            // 表示モード
            Group {
                Text("表示モード").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $s.viewMode) {
                    ForEach(DisplaySettings.ViewMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: s.viewMode) { _, _ in s.save() }
            }

            Divider()

            // 背景色
            Text("背景色").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $s.gridBackground) {
                ForEach(DisplaySettings.GridBackground.allCases, id: \.self) { bg in
                    Text(bg.rawValue).tag(bg)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: s.gridBackground) { _, _ in s.save() }

            Divider()

            if s.viewMode == .grid {
                // グリッド設定
                Text("サムネイルサイズ").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $s.thumbSize) {
                    ForEach(DisplaySettings.ThumbSize.allCases, id: \.self) { sz in
                        Text(sz.rawValue).tag(sz)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: s.thumbSize) { _, _ in s.save() }

                Text("バッジフォント").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $s.badgeFont) {
                    ForEach(DisplaySettings.BadgeFont.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: s.badgeFont) { _, _ in s.save() }

                Divider()

                Text("画像上のバッジ").font(.caption).foregroundStyle(.secondary)
                Toggle("撮影地", isOn: $s.showLocation).onChange(of: s.showLocation) { _, _ in s.save() }
                Toggle("タグ",   isOn: $s.showTags).onChange(of: s.showTags)         { _, _ in s.save() }
                Toggle("★評価", isOn: $s.showRating).onChange(of: s.showRating)     { _, _ in s.save() }

                Divider()

                Text("画像下の情報").font(.caption).foregroundStyle(.secondary)
                Toggle("ファイル名", isOn: $s.showFilename).onChange(of: s.showFilename) { _, _ in s.save() }
                Toggle("撮影日時",   isOn: $s.showShotDate).onChange(of: s.showShotDate) { _, _ in s.save() }

            } else {
                // リスト列設定
                Text("表示する列").font(.caption).foregroundStyle(.secondary)
                Text("★ = ファイル読み込みが必要").font(.caption2).foregroundStyle(.tertiary)

                ForEach(ListColumn.allCases) { col in
                    let isOn = s.listColumns.contains(col)
                    Toggle(col.needsEXIF ? "\(col.label) ★" : col.label, isOn: Binding(
                        get: { s.listColumns.contains(col) },
                        set: { on in
                            if on { s.listColumns.insert(col) } else { s.listColumns.remove(col) }
                            s.save()
                        }
                    ))
                    .font(col.needsEXIF ? .callout.italic() : .callout)
                }
            }
        }
        .padding(16)
        .frame(width: 230)
    }
}

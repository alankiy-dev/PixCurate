import SwiftUI

struct DisplaySettingsView: View {
    @Environment(DisplaySettings.self) var settings

    var body: some View {
        @Bindable var s = settings
        VStack(alignment: .leading, spacing: 16) {
            Text("表示設定").font(.headline)

            Divider()

            Group {
                Text("サムネイルサイズ").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $s.thumbSize) {
                    ForEach(DisplaySettings.ThumbSize.allCases, id: \.self) { sz in
                        Text(sz.rawValue).tag(sz)
                    }
                }
                .pickerStyle(.segmented)
            }

            Group {
                Text("バッジフォント").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $s.badgeFont) {
                    ForEach(DisplaySettings.BadgeFont.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            Text("画像上のバッジ").font(.caption).foregroundStyle(.secondary)
            Toggle("撮影地", isOn: $s.showLocation)
            Toggle("タグ",   isOn: $s.showTags)
            Toggle("★評価", isOn: $s.showRating)

            Divider()

            Text("画像下の情報").font(.caption).foregroundStyle(.secondary)
            Toggle("ファイル名", isOn: $s.showFilename)
            Toggle("撮影日時",   isOn: $s.showShotDate)
        }
        .padding(16)
        .frame(width: 220)
        .onChange(of: settings.thumbSize)   { _, _ in settings.save() }
        .onChange(of: settings.badgeFont)   { _, _ in settings.save() }
        .onChange(of: settings.showLocation){ _, _ in settings.save() }
        .onChange(of: settings.showTags)    { _, _ in settings.save() }
        .onChange(of: settings.showRating)  { _, _ in settings.save() }
        .onChange(of: settings.showFilename){ _, _ in settings.save() }
        .onChange(of: settings.showShotDate){ _, _ in settings.save() }
    }
}

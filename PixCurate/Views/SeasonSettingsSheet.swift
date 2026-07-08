import SwiftUI

/// 季節ごとの対象月を設定するシート。各月がどの季節に属するかを選ぶ。
struct SeasonSettingsSheet: View {
    /// 月割り当てが変わったか（changed）を渡す。変わっていなければ呼び出し側で再適用を省ける
    var onClose: (_ changed: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = SeasonSettings.shared
    @State private var initialMap: [Int: Season] = [:]

    private let months = Array(1...12)
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.teal)
                Text("季節の設定")
                    .font(.title3).bold()
                Spacer()
                Button {
                    settings.resetToDefault()
                } label: {
                    Label("初期値に戻す", systemImage: "arrow.counterclockwise")
                }
                .help("春3-5 / 夏6-8 / 秋9-11 / 冬12,1,2 に戻す")
            }

            Text("各月がどの季節に属するかを設定します。フィルターの季節はこの割り当てで判定されます。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 季節ごとの現在の月まとめ（各チップ等幅・1行で統一）
            HStack(spacing: 8) {
                ForEach(Season.allCases) { season in
                    let ms = settings.months(for: season)
                    HStack(spacing: 4) {
                        Image(systemName: season.symbol)
                            .foregroundStyle(season.color)
                        Text(season.label)
                            .fontWeight(.semibold)
                        Text(ms.map(String.init).joined(separator: "・") + "月")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(season.color.opacity(0.10)))
                }
            }

            Divider()

            // 月ごとの季節割り当て
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(months, id: \.self) { month in
                    HStack {
                        Text("\(month)月")
                            .frame(width: 40, alignment: .leading)
                            .fontWeight(.medium)
                        Picker("", selection: Binding(
                            get: { settings.season(forMonth: month) ?? .spring },
                            set: { settings.setSeason($0, forMonth: month) }
                        )) {
                            ForEach(Season.allCases) { season in
                                Text(season.label).tag(season)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                }
            }

            HStack {
                Spacer()
                Button("閉じる") {
                    onClose(settings.monthSeason != initialMap)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { initialMap = settings.monthSeason }
    }
}

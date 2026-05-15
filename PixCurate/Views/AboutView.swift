import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 0) {
            // アイコン＋タイトル
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

                Text("PixCurate")
                    .font(.system(size: 26, weight: .bold))

                Text("Version \(version) (Build \(build))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 20)

            Divider()

            // 説明
            VStack(spacing: 8) {
                Text("RAW写真のメタデータ管理・選別・\nバックアップのための macOS アプリ")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(["RAF", "ARW", "CR3"], id: \.self) { fmt in
                        Text(fmt)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(.vertical, 20)

            Divider()

            // コピーライト
            VStack(spacing: 4) {
                Text("© 2026 Alankiy@レタッチラボ")
                    .font(.callout)
                    .fontWeight(.medium)

                Text("All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)

            Divider()

            // 閉じるボタン
            Button("閉じる") { dismiss() }
                .keyboardShortcut(.escape)
                .padding(.vertical, 16)
        }
        .frame(width: 340)
        .fixedSize()
    }
}

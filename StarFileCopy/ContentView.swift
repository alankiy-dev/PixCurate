import SwiftUI

// MARK: - UserDefaults keys
private enum Keys {
    static let srcPath       = "srcPath"
    static let dstPath       = "dstPath"
    static let useSinceFilter = "useSinceFilter"
    static let sinceDate     = "sinceDate"
    static let keepStructure = "keepStructure"
    static let minRating     = "minRating"
}

struct ContentView: View {

    // MARK: - State

    @StateObject private var engine = CopyEngine()

    @State private var srcURL: URL? = restore(Keys.srcPath)
    @State private var dstURL: URL? = restore(Keys.dstPath)
    @State private var sinceDate: Date = UserDefaults.standard.object(forKey: Keys.sinceDate) as? Date
                                         ?? Calendar.current.startOfDay(for: Date())
    @State private var useSinceFilter: Bool = UserDefaults.standard.object(forKey: Keys.useSinceFilter) as? Bool ?? true
    @State private var keepStructure: Bool  = UserDefaults.standard.bool(forKey: Keys.keepStructure)
    @State private var minRating: Int       = UserDefaults.standard.object(forKey: Keys.minRating) as? Int ?? 1
    @State private var logLines: [String]   = []
    @State private var isRunning: Bool      = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── ヘッダー ──────────────────────────────
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("星マーク写真コピー")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── フォルダ選択 ──────────────────────
                    GroupBox(label: Label("フォルダ設定", systemImage: "folder")) {
                        VStack(spacing: 12) {
                            FolderPickerRow(
                                label: "コピー元",
                                url: $srcURL,
                                placeholder: "選択してください"
                            )
                            .onChange(of: srcURL) { newVal in
                                save(url: newVal, key: Keys.srcPath)
                            }
                            FolderPickerRow(
                                label: "コピー先",
                                url: $dstURL,
                                placeholder: "選択してください"
                            )
                            .onChange(of: dstURL) { newVal in
                                save(url: newVal, key: Keys.dstPath)
                            }
                        }
                        .padding(.top, 8)
                    }

                    // ── オプション ────────────────────────
                    GroupBox(label: Label("オプション", systemImage: "slider.horizontal.3")) {
                        VStack(alignment: .leading, spacing: 14) {

                            // 日付フィルター
                            HStack {
                                Toggle("更新日フィルター", isOn: $useSinceFilter)
                                    .onChange(of: useSinceFilter) { v in
                                        UserDefaults.standard.set(v, forKey: Keys.useSinceFilter)
                                    }
                                Spacer()
                                if useSinceFilter {
                                    DatePicker(
                                        "",
                                        selection: $sinceDate,
                                        displayedComponents: .date
                                    )
                                    .labelsHidden()
                                    .frame(width: 130)
                                    .onChange(of: sinceDate) { v in
                                        UserDefaults.standard.set(v, forKey: Keys.sinceDate)
                                    }
                                }
                            }
                            if useSinceFilter {
                                Text("指定日以降に更新された .xmp ファイルを持つ写真のみ対象")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            // フォルダ構造維持
                            Toggle("フォルダ構造を維持してコピー", isOn: $keepStructure)
                                .onChange(of: keepStructure) { v in
                                    UserDefaults.standard.set(v, forKey: Keys.keepStructure)
                                }

                            Divider()

                            // 最低レーティング
                            HStack {
                                Text("最低レーティング")
                                Spacer()
                                HStack(spacing: 4) {
                                    ForEach(1...5, id: \.self) { star in
                                        Image(systemName: star <= minRating ? "star.fill" : "star")
                                            .foregroundColor(star <= minRating ? .yellow : .gray)
                                            .font(.title3)
                                            .onTapGesture {
                                                minRating = star
                                                UserDefaults.standard.set(star, forKey: Keys.minRating)
                                            }
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }

                    // ── ログ ──────────────────────────────
                    GroupBox(label: Label("ログ", systemImage: "terminal")) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    if logLines.isEmpty {
                                        Text("実行ログがここに表示されます...")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 12, design: .monospaced))
                                    } else {
                                        ForEach(Array(logLines.enumerated()), id: \.offset) { idx, line in
                                            Text(line)
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundColor(logColor(line))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .id(idx)
                                        }
                                    }
                                }
                                .padding(8)
                            }
                            .frame(height: 160)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .onChange(of: logLines.count) { _ in
                                if let last = logLines.indices.last {
                                    proxy.scrollTo(last, anchor: .bottom)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }

                    // ── ボタン ────────────────────────────
                    HStack(spacing: 12) {
                        Button {
                            execute(dryRun: true)
                        } label: {
                            Label("プレビュー", systemImage: "eye")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isRunning || srcURL == nil || dstURL == nil)

                        Button {
                            execute(dryRun: false)
                        } label: {
                            Label("コピー実行", systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning || srcURL == nil || dstURL == nil)
                    }

                    if isRunning {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("処理中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 680)
    }

    // MARK: - Actions

    private func execute(dryRun: Bool) {
        guard let src = srcURL, let dst = dstURL else { return }
        logLines = []
        isRunning = true

        let since = useSinceFilter ? sinceDate : Date(timeIntervalSince1970: 0)
        let min = minRating
        let keep = keepStructure

        DispatchQueue.global(qos: .userInitiated).async {
            let result = engine.run(
                src: src,
                dst: dst,
                since: since,
                minRating: min,
                maxRating: 5,
                keepStructure: keep,
                dryRun: dryRun,
                log: { line in
                    DispatchQueue.main.async {
                        logLines.append(line)
                    }
                }
            )
            DispatchQueue.main.async {
                logLines.append("══════════════════════════════════")
                if dryRun {
                    logLines.append("✅ プレビュー対象  : \(result.copied) ファイル")
                } else {
                    logLines.append("✅ コピー完了      : \(result.copied) ファイル")
                }
                logLines.append("⏭  スキップ（日付）  : \(result.skippedDate) ファイル")
                logLines.append("⏭  スキップ（同一）    : \(result.skippedSame) ファイル")
                logLines.append("⏭  スキップ（星なし）: \(result.skippedRating) ファイル")
                logLines.append("⬜ .xmpなし          : \(result.noXmp) ファイル")
                if result.errors > 0 {
                    logLines.append("❌ エラー            : \(result.errors) ファイル")
                }
                logLines.append("══════════════════════════════════")
                isRunning = false
            }
        }
    }

    private func logColor(_ line: String) -> Color {
        if line.hasPrefix("❌") { return .red }
        if line.hasPrefix("✅") { return .green }
        if line.hasPrefix("★") { return .primary }
        if line.hasPrefix("  [プレビュー") { return .blue }
        return .secondary
    }
}

// MARK: - UserDefaults helpers

/// URL を bookmark data として保存（外部ボリューム対応）
private func save(url: URL?, key: String) {
    guard let url = url,
          let data = try? url.bookmarkData(
              options: .withSecurityScope,
              includingResourceValuesForKeys: nil,
              relativeTo: nil
          ) else {
        UserDefaults.standard.removeObject(forKey: key)
        return
    }
    UserDefaults.standard.set(data, forKey: key)
}

/// bookmark data から URL を復元
private func restore(_ key: String) -> URL? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    var stale = false
    let url = try? URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &stale
    )
    if stale, let url = url {
        save(url: url, key: key)
    }
    _ = url?.startAccessingSecurityScopedResource()
    return url
}

// MARK: - FolderPickerRow

struct FolderPickerRow: View {
    let label: String
    @Binding var url: URL?
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 60, alignment: .leading)
                .foregroundColor(.secondary)
                .font(.callout)

            Text(url?.path ?? placeholder)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(url == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )

            Button("選択...") {
                selectFolder()
            }
            .frame(width: 60)
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "\(label)を選択"
        if panel.runModal() == .OK {
            url = panel.url
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}

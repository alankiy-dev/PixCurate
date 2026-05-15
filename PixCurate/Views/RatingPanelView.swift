import SwiftUI

struct RatingPanelView: View {
    let selectedFiles: [PhotoFile]
    let vm: FileListViewModel

    @State private var pendingRating: Int? = nil
    @State private var isWriting = false

    private var currentRating: Int? {
        guard !selectedFiles.isEmpty else { return nil }
        let ratings = selectedFiles.map { $0.rating }
        let first = ratings[0]
        return ratings.allSatisfy { $0 == first } ? first : nil
    }

    private var displayRating: Int {
        pendingRating ?? currentRating ?? 0
    }

    private var isMixed: Bool {
        guard pendingRating == nil else { return false }
        let ratings = selectedFiles.map { $0.rating }
        return ratings.dropFirst().contains { $0 != ratings.first }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("評価")
                    .font(.headline)
                if !selectedFiles.isEmpty {
                    Text("(\(selectedFiles.count)件)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if selectedFiles.isEmpty {
                Spacer()
                Text("画像を選択してください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(spacing: 20) {
                    Spacer()

                    // 現在の評価表示
                    if isMixed {
                        Text("複数の評価が混在しています")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(displayRating == 0 ? "未評価" : String(repeating: "★", count: displayRating))
                            .font(.title2)
                            .foregroundStyle(displayRating > 0 ? .yellow : .secondary)
                    }

                    // 星ピッカー
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= displayRating ? "star.fill" : "star")
                                    .font(.system(size: 28))
                                    .foregroundStyle(star <= displayRating ? .yellow : .secondary.opacity(0.4))
                                    .onTapGesture {
                                        pendingRating = (pendingRating == star && star == displayRating) ? 0 : star
                                    }
                                    .animation(.easeInOut(duration: 0.1), value: displayRating)
                            }
                        }

                        Button("未評価に戻す") {
                            pendingRating = 0
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }

                    if let pending = pendingRating {
                        Text(pending == 0 ? "未評価に変更 (未保存)" : "★\(pending) に変更 (未保存)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Write button
                Group {
                    if isWriting {
                        HStack {
                            ProgressView().scaleEffect(0.6)
                            Text("書き込み中...").font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Button { applyRating() } label: {
                            Label("評価を書き込む", systemImage: "star.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pendingRating == nil)
                        .help(pendingRating == nil ? "星をタップして評価を選択してください" : "選択した\(selectedFiles.count)件に書き込む")
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 200)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: selectedFiles.map { $0.id }) { _, _ in pendingRating = nil }
    }

    private func applyRating() {
        guard let rating = pendingRating else { return }
        let files = selectedFiles
        isWriting = true

        Task.detached(priority: .userInitiated) {
            var updates: [(URL, Int?)] = []
            for file in files {
                let newRating = rating == 0 ? nil : rating
                _ = XMPService.writeRating(to: file.xmpURL, rating: rating)
                updates.append((file.rawURL, newRating))
            }
            let finalUpdates = updates
            await MainActor.run {
                for (url, r) in finalUpdates {
                    vm.updateRating(for: url, rating: r)
                }
                pendingRating = nil
                isWriting = false
            }
        }
    }
}

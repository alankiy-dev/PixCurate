import SwiftUI

struct RatingPanelView: View {
    let selectedFiles: [PhotoFile]
    let vm: FileListViewModel

    @State private var isColorWriting = false

    // MARK: - Rating state

    private var currentRating: Int? {
        guard !selectedFiles.isEmpty else { return nil }
        let ratings = selectedFiles.map { $0.rating }
        let first = ratings[0]
        return ratings.allSatisfy { $0 == first } ? first : nil
    }

    private var displayRating: Int { currentRating ?? 0 }

    private var isMixed: Bool {
        guard selectedFiles.count > 1 else { return false }
        let ratings = selectedFiles.map { $0.rating }
        return ratings.dropFirst().contains { $0 != ratings.first }
    }

    // MARK: - Color label state

    /// 選択中ファイルのカラーラベルが全て同一なら その値、混在なら nil
    private var currentColorLabel: ColorLabel? {
        guard !selectedFiles.isEmpty else { return nil }
        let labels = selectedFiles.map { $0.colorLabel }
        let first = labels[0]
        return labels.allSatisfy { $0 == first } ? first : nil
    }

    private var isColorLabelMixed: Bool {
        guard selectedFiles.count > 1 else { return false }
        let labels = selectedFiles.map { $0.colorLabel }
        return labels.dropFirst().contains { $0 != labels.first }
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

                    // 星ピッカー（即時書き込み）
                    VStack(spacing: 6) {
                        Text("レーティング")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isMixed {
                            Text("評価が混在しています")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= displayRating ? "star.fill" : "star")
                                    .font(.system(size: 22))
                                    .foregroundStyle(star <= displayRating ? .yellow : .secondary.opacity(0.4))
                                    .onTapGesture {
                                        // 同じ星を再タップ → 解除
                                        let newRating = (star == displayRating) ? 0 : star
                                        applyRating(newRating)
                                    }
                                    .animation(.easeInOut(duration: 0.1), value: displayRating)
                            }
                        }
                    }

                    Divider()

                    // カラーラベルセクション
                    colorLabelPicker

                    Spacer()
                }
                .frame(maxWidth: .infinity)

            }
        }
        .frame(width: 200)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Color label picker

    private var colorLabelPicker: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("カラーラベル")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isColorLabelMixed {
                    Text("（混在）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // カラーボタン行
            HStack(spacing: 10) {
                ForEach(ColorLabel.allCases, id: \.self) { label in
                    let isActive = !isColorLabelMixed && currentColorLabel == label
                    Button {
                        // 同じラベルを再クリック → 解除
                        applyColorLabel(isActive ? nil : label)
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(label.color)
                            .overlay(
                                isActive
                                ? AnyView(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(label.color.opacity(0.7), lineWidth: 2)
                                        .padding(-4)
                                )
                                : AnyView(EmptyView())
                            )
                    }
                    .buttonStyle(.plain)
                    .help(label.localizedName + "（" + String(label.keyChar).uppercased() + "キー）")
                }
            }
            .padding(.horizontal, 12)

            if isColorWriting {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5)
                    Text("書き込み中...").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func applyRating(_ rating: Int) {
        let newRating: Int? = rating == 0 ? nil : rating
        let files = selectedFiles
        Task.detached(priority: .userInitiated) {
            for file in files {
                _ = XMPService.writeRating(to: file.xmpURL, rating: rating)
            }
            let urls = files.map { $0.rawURL }
            await MainActor.run {
                for url in urls {
                    vm.updateRating(for: url, rating: newRating)
                }
            }
        }
    }

    private func applyColorLabel(_ label: ColorLabel?) {
        let files = selectedFiles
        isColorWriting = true

        Task.detached(priority: .userInitiated) {
            for file in files {
                _ = XMPService.writeColorLabel(to: file.xmpURL, label: label)
            }
            let urls = files.map { $0.rawURL }
            await MainActor.run {
                for url in urls {
                    vm.updateColorLabel(for: url, colorLabel: label)
                }
                isColorWriting = false
            }
        }
    }
}

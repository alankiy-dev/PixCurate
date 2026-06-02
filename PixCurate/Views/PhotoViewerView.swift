import SwiftUI
import AppKit

struct PhotoViewerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1.0
    @GestureState private var dragDelta: CGSize = .zero

    /// 現在のファイルの評価（DB から読み込み、キー操作で更新）
    @State private var currentRating: Int? = nil
    /// 評価変更フィードバック用（一時的に大きく表示）
    @State private var ratingFeedback: Int? = nil
    @FocusState private var isFocused: Bool

    private var effectiveOffset: CGSize {
        CGSize(width: offset.width + dragDelta.width,
               height: offset.height + dragDelta.height)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale * magnifyBy)
                    .offset(effectiveOffset)
                    .gesture(
                        MagnifyGesture()
                            .updating($magnifyBy) { value, state, _ in
                                state = value.magnification
                            }
                            .onEnded { value in
                                scale = max(1.0, scale * value.magnification)
                                if scale == 1.0 { offset = .zero }
                            }
                    )
                    .gesture(
                        DragGesture()
                            .updating($dragDelta) { value, state, _ in
                                if scale > 1.0 { state = value.translation }
                            }
                            .onEnded { value in
                                if scale > 1.0 {
                                    offset = CGSize(
                                        width:  offset.width  + value.translation.width,
                                        height: offset.height + value.translation.height
                                    )
                                } else {
                                    offset = .zero
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.25)) {
                            scale = 1.0
                            offset = .zero
                        }
                    }
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("読み込み中...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Image(systemName: "photo.slash")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // 下部オーバーレイ：ファイル名 ＋ 評価
            VStack {
                Spacer()
                HStack(alignment: .center, spacing: 12) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    // 評価バッジ
                    HStack(spacing: 3) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: (currentRating ?? 0) >= i ? "star.fill" : "star")
                                .font(.system(size: 14))
                                .foregroundStyle((currentRating ?? 0) >= i ? Color.yellow : Color.white.opacity(0.3))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55))
                .padding(.bottom, 0)
            }

            // 評価変更フィードバック（中央に一瞬表示）
            if let fb = ratingFeedback {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: fb >= i ? "star.fill" : "star")
                                .font(.system(size: 28))
                                .foregroundStyle(fb >= i ? Color.yellow : Color.white.opacity(0.25))
                        }
                    }
                    if fb == 0 {
                        Text("評価を解除")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(minWidth: 960, minHeight: 720)
        .navigationTitle(url.lastPathComponent)
        .focusable()
        .focused($isFocused)
        // ESC で閉じる
        .onKeyPress(.escape) {
            closeWindow()
            return .handled
        }
        // 数字キー 0〜5 で評価
        .onKeyPress(phases: .down) { press in
            if let rating = ratingFromKey(press.key) {
                applyRating(rating)
                return .handled
            }
            return .ignored
        }
        .onAppear { isFocused = true }
        .task(id: url) {
            isLoading = true
            image = nil
            scale = 1.0
            offset = .zero
            ratingFeedback = nil
            // 評価を DB から読み込む
            currentRating = IndexService.loadRating(for: url)
            image = await ThumbnailService.fullPreview(for: url)
            isLoading = false
        }
    }

    // MARK: - Actions

    private func closeWindow() {
        // SwiftUI の dismiss は WindowGroup では効かない場合があるため NSApp 経由も併用
        if let w = NSApp.keyWindow { w.close() }
        dismiss()
    }

    private func ratingFromKey(_ key: KeyEquivalent) -> Int? {
        switch key {
        case "0": return 0
        case "1": return 1
        case "2": return 2
        case "3": return 3
        case "4": return 4
        case "5": return 5
        default:  return nil
        }
    }

    private func applyRating(_ rating: Int) {
        let newRating: Int? = rating == 0 ? nil : rating
        currentRating = newRating

        // フィードバック表示（0.8秒後に消す）
        withAnimation(.easeIn(duration: 0.1)) { ratingFeedback = rating }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(.easeOut(duration: 0.2)) { ratingFeedback = nil }
        }

        // XMP に書き込み
        let xmpURL = url.deletingPathExtension().appendingPathExtension("xmp")
        Task.detached(priority: .userInitiated) {
            _ = XMPService.writeRating(to: xmpURL, rating: rating)
            // メインウィンドウの ViewModel に通知
            NotificationCenter.default.post(
                name: .photoRatingChanged,
                object: nil,
                userInfo: ["url": url, "rating": newRating as Any]
            )
        }
    }
}

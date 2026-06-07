import SwiftUI
import AppKit

struct PhotoViewerView: View {
    let url: URL
    var sizeMode: DisplaySettings.ViewerSize = .fit
    @Environment(\.dismiss) private var dismiss

    @State private var window: NSWindow?
    @State private var didApplySize = false

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1.0
    @GestureState private var dragDelta: CGSize = .zero

    /// 現在のファイルの評価（DB から読み込み、キー操作で更新）
    @State private var currentRating: Int? = nil
    /// 現在のファイルのカラーラベル
    @State private var currentColorLabel: ColorLabel? = nil
    /// 評価変更フィードバック用（一時的に大きく表示）
    @State private var ratingFeedback: Int? = nil
    /// カラーラベル変更フィードバック（表示中かどうか）
    @State private var showColorLabelFeedback = false
    /// カラーラベル変更フィードバックの値（nil = 解除）
    @State private var colorLabelFeedbackValue: ColorLabel? = nil
    @FocusState private var isFocused: Bool

    private var effectiveOffset: CGSize {
        CGSize(width: offset.width + dragDelta.width,
               height: offset.height + dragDelta.height)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let img = image {
                GeometryReader { geo in
                    let vw = geo.size.width
                    let vh = geo.size.height
                    let imgPx = pixelSize(of: img)
                    // ベース倍率：ピクセル等倍は 100%、それ以外は画面に収まるように縮小（縦横中央）
                    let baseScale: CGFloat = (sizeMode == .pixel)
                        ? 1.0
                        : min(vw / imgPx.width, vh / imgPx.height)
                    let dispW = imgPx.width  * baseScale * scale * magnifyBy
                    let dispH = imgPx.height * baseScale * scale * magnifyBy

                    ZStack {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: dispW, height: dispH)
                            .offset(effectiveOffset)
                    }
                    .frame(width: vw, height: vh)   // ビューポート内で中央寄せ
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        MagnifyGesture()
                            .updating($magnifyBy) { value, state, _ in
                                state = value.magnification
                            }
                            .onEnded { value in
                                scale = max(1.0, scale * value.magnification)
                                let dw = imgPx.width  * baseScale * scale
                                let dh = imgPx.height * baseScale * scale
                                offset = clampedOffset(offset,
                                                       dispSize: CGSize(width: dw, height: dh),
                                                       viewport: CGSize(width: vw, height: vh))
                            }
                    )
                    .gesture(
                        DragGesture()
                            .updating($dragDelta) { value, state, _ in
                                if dispW > vw || dispH > vh { state = value.translation }
                            }
                            .onEnded { value in
                                let dw = imgPx.width  * baseScale * scale
                                let dh = imgPx.height * baseScale * scale
                                let proposed = CGSize(
                                    width:  offset.width  + value.translation.width,
                                    height: offset.height + value.translation.height
                                )
                                offset = clampedOffset(proposed,
                                                       dispSize: CGSize(width: dw, height: dh),
                                                       viewport: CGSize(width: vw, height: vh))
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.25)) {
                            scale = 1.0
                            offset = .zero
                        }
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

            // 下部オーバーレイ：ファイル名 ＋ カラーラベル ＋ 評価
            VStack {
                Spacer()
                HStack(alignment: .center, spacing: 12) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    // カラーラベルドット
                    if let label = currentColorLabel {
                        Circle()
                            .fill(label.color)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.6), lineWidth: 1)
                            )
                    }

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

            // カラーラベル変更フィードバック（評価フィードバックより上に表示）
            if showColorLabelFeedback {
                VStack(spacing: 6) {
                    if let label = colorLabelFeedbackValue {
                        Circle()
                            .fill(label.color)
                            .frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
                        Text(label.localizedName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    } else {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                                .frame(width: 44, height: 44)
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Text("ラベルを解除")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .offset(y: -60)  // 評価フィードバックと重ならないようにオフセット
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
        .frame(minWidth: 320, minHeight: 240)
        .background(WindowAccessor { win in
            if window !== win { window = win }
            applyWindowSize()
        })
        .navigationTitle(url.lastPathComponent)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        // ESC で閉じる
        .onKeyPress(.escape) {
            closeWindow()
            return .handled
        }
        // 数字キー 0〜5 で評価 / r,y,g,b,p,x でカラーラベル
        .onKeyPress(phases: .down) { press in
            if let rating = ratingFromKey(press.key) {
                applyRating(rating)
                return .handled
            }
            if press.modifiers.isEmpty, let ch = press.characters.first {
                switch ch {
                case "r": applyColorLabel(.red);    return .handled
                case "y": applyColorLabel(.yellow); return .handled
                case "g": applyColorLabel(.green);  return .handled
                case "b": applyColorLabel(.blue);   return .handled
                case "p": applyColorLabel(.purple); return .handled
                case "x": applyColorLabel(nil);     return .handled
                default: break
                }
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
            showColorLabelFeedback = false
            // メタデータを読み込む
            currentRating = IndexService.loadRating(for: url)
            currentColorLabel = XMPService.readColorLabel(xmpURL: url.deletingPathExtension().appendingPathExtension("xmp"))
            image = await ThumbnailService.fullPreview(for: url)
            isLoading = false
            applyWindowSize()   // ピクセル等倍は画像サイズ確定後に適用
        }
    }

    // MARK: - ウィンドウサイズ

    private func applyWindowSize() {
        guard let window, !didApplySize else { return }
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        switch sizeMode {
        case .normal:
            didApplySize = true
            let size = NSSize(width: min(960, visible.width),
                              height: min(720, visible.height))
            window.setContentSize(size)
            window.center()
        case .fit:
            didApplySize = true
            window.setFrame(visible, display: true)
        case .pixel:
            // 画像の実ピクセルサイズが必要なので、画像読み込み後に適用する
            guard let img = image else { return }
            didApplySize = true
            let px = pixelSize(of: img)
            let w = min(px.width, visible.width)
            let h = min(px.height, visible.height)
            window.setContentSize(NSSize(width: w, height: h))
            window.center()
        }
    }

    /// パン位置を画像が画面外に行き過ぎないようにクランプ（中央基準）
    private func clampedOffset(_ proposed: CGSize, dispSize: CGSize, viewport: CGSize) -> CGSize {
        let maxX = max(0, (dispSize.width  - viewport.width)  / 2)
        let maxY = max(0, (dispSize.height - viewport.height) / 2)
        return CGSize(
            width:  min(max(proposed.width,  -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func pixelSize(of img: NSImage) -> CGSize {
        for rep in img.representations where rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return img.size
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

    private func applyColorLabel(_ label: ColorLabel?) {
        currentColorLabel = label

        // フィードバック表示（0.8秒後に消す）
        withAnimation(.easeIn(duration: 0.1)) {
            colorLabelFeedbackValue = label
            showColorLabelFeedback = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(.easeOut(duration: 0.2)) { showColorLabelFeedback = false }
        }

        // XMP に書き込み
        let xmpURL = url.deletingPathExtension().appendingPathExtension("xmp")
        Task.detached(priority: .userInitiated) {
            _ = XMPService.writeColorLabel(to: xmpURL, label: label)
            NotificationCenter.default.post(
                name: .photoColorLabelChanged,
                object: nil,
                userInfo: ["url": url, "colorLabel": label?.rawValue as Any]
            )
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

// MARK: - WindowAccessor（ホスト中の NSWindow を取得）

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let w = view.window { onResolve(w) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let w = nsView.window { onResolve(w) }
        }
    }
}

import SwiftUI
import AppKit

struct PhotoViewerView: View {
    let url: URL
    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero          // 累積オフセット
    @GestureState private var magnifyBy: CGFloat = 1.0
    @GestureState private var dragDelta: CGSize = .zero // 現在のドラッグ量（ジェスチャー中のみ）

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

            if image != nil {
                VStack {
                    Spacer()
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.bottom, 16)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 720)
        .navigationTitle(url.lastPathComponent)
        .task(id: url) {
            isLoading = true
            image = nil
            scale = 1.0
            offset = .zero
            image = await ThumbnailService.fullPreview(for: url)
            isLoading = false
        }
    }
}

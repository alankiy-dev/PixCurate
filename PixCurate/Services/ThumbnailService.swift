import AppKit
import ImageIO

enum ThumbnailService {
    // MainActor上でキャッシュ管理（サイズ別にキャッシュ）
    @MainActor private static var cache: [URL: NSImage] = [:]
    @MainActor private static var fullCache: [URL: NSImage] = [:]

    // 常に大サイズで生成してキャッシュ。縮小表示は SwiftUI に任せる（縮小は綺麗、拡大は汚い）
    private static let fixedMaxPixel = 600

    /// CGImageSourceでインプロセスにサムネイル生成（サンドボックス対応）
    static func thumbnail(for url: URL, maxPixel: Int = 320) async -> NSImage? {
        if let cached = await MainActor.run(body: { cache[url] }) {
            return cached
        }

        let image = await Task.detached(priority: .userInitiated) {
            Self.load(url: url, maxPixel: Self.fixedMaxPixel)
        }.value

        if let image {
            await MainActor.run { cache[url] = image }
        }
        return image
    }

    /// RAWに埋め込まれた最大サイズのJPEGプレビューをフル解像度で読み込む
    static func fullPreview(for url: URL) async -> NSImage? {
        if let cached = await MainActor.run(body: { fullCache[url] }) {
            return cached
        }

        let image = await Task.detached(priority: .userInitiated) {
            Self.loadFullPreview(url: url)
        }.value

        if let image {
            await MainActor.run { fullCache[url] = image }
        }
        return image
    }

    /// RAWファイルの埋め込みJPEGプレビューを優先して読み込む
    nonisolated private static func load(url: URL, maxPixel: Int) -> NSImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else {
            return NSImage(contentsOf: url).map { scaled($0, maxPixel: maxPixel) }
        }

        // Step 1: 埋め込みサムネイルのみを高速取得（フルRAW展開しない）
        let quickOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, quickOptions as CFDictionary) {
            return NSImage(cgImage: cgImage, size: .zero)
        }

        // Step 2: RAF など複数サブイメージを持つ形式 → 全インデックスを探索
        let count = CGImageSourceGetCount(source)
        for i in 0..<count {
            let opts: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, i, opts as CFDictionary) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
            // サムネイルAPIで取れなくてもサブイメージ自体が小さければ直接使う
            let directOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, directOpts as CFDictionary) {
                let pixels = cgImage.width * cgImage.height
                // 本体RAW（数千万画素）は除外し、プレビュー相当（2000万画素未満）のみ採用
                if pixels > 0 && pixels < 20_000_000 {
                    return NSImage(cgImage: cgImage, size: .zero)
                }
            }
        }

        // Step 3: 小ファイル（50MB未満）のみフルデコードへフォールバック
        if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize < 50_000_000 {
            let fullOptions: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, fullOptions as CFDictionary) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
        }

        return nil
    }

    /// サイズ制限なしで埋め込みJPEGプレビューを取得する
    nonisolated private static func loadFullPreview(url: URL) -> NSImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        // まず補助イメージ（埋め込みJPEGプレビュー）を探す
        let count = CGImageSourceGetCount(source)
        var bestImage: CGImage?
        var bestPixels = 0

        for i in 0..<count {
            let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
            if let cgImg = CGImageSourceCreateImageAtIndex(source, i, opts as CFDictionary) {
                let pixels = cgImg.width * cgImg.height
                if pixels > bestPixels {
                    bestPixels = pixels
                    bestImage = cgImg
                }
            }
        }

        if let cgImg = bestImage {
            return NSImage(cgImage: cgImg, size: .zero)
        }

        // フォールバック: サムネイルAPIで大きめに取得
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 8000,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let cgImg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
            return NSImage(cgImage: cgImg, size: .zero)
        }

        return NSImage(contentsOf: url)
    }

    nonisolated private static func scaled(_ image: NSImage, maxPixel: Int) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = CGFloat(maxPixel) / max(size.width, size.height)
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: newSize)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        result.unlockFocus()
        return result
    }
}

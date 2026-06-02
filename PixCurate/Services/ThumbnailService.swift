import AppKit
import ImageIO

enum ThumbnailService {
    // MainActor上でキャッシュ管理
    @MainActor private static var cache: [URL: NSImage] = [:]
    @MainActor private static var fullCache: [URL: NSImage] = [:]
    /// 取得を試みて失敗したURL。再レンダリングのたびに何度もエラーログが出るのを防ぐ
    @MainActor private static var failedURLs: Set<URL> = []

    // 常に大サイズで生成してキャッシュ。縮小表示は SwiftUI に任せる
    private static let fixedMaxPixel = 600

    static func thumbnail(for url: URL, maxPixel: Int = 320) async -> NSImage? {
        // キャッシュヒット
        if let cached = await MainActor.run(body: { cache[url] }) {
            return cached
        }
        // 過去に失敗済みのURLは再試行しない
        let alreadyFailed = await MainActor.run { failedURLs.contains(url) }
        if alreadyFailed { return nil }

        let image = await Task.detached(priority: .userInitiated) {
            Self.load(url: url, maxPixel: Self.fixedMaxPixel)
        }.value
        await MainActor.run {
            if let image {
                cache[url] = image
            } else {
                failedURLs.insert(url)   // 失敗を記録して次回はスキップ
            }
        }
        return image
    }

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

    /// 再スキャン・フォルダ切り替え時に失敗キャッシュをリセットして再試行を許可する
    @MainActor static func resetFailedURLs() {
        failedURLs.removeAll()
    }

    // MARK: - Thumbnail load

    nonisolated private static func load(url: URL, maxPixel: Int) -> NSImage? {
        // RAF ファイルはヘッダーを直接読んで埋め込み JPEG を抽出（フル RAW デコード回避）
        if url.pathExtension.uppercased() == "RAF" {
            if let img = loadRAFThumbnail(url: url, maxPixel: maxPixel) {
                return img
            }
        }

        return loadViaCGImageSource(url: url, maxPixel: maxPixel)
    }

    /// RAF ヘッダーから JPEG オフセットを読み取り、最初の 256KB だけで EXIF サムネイルを抽出
    /// 200MB のファイルでも実際の I/O は ~256KB で済む
    nonisolated private static func loadRAFThumbnail(url: URL, maxPixel: Int) -> NSImage? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        // RAF ヘッダー先頭 92 バイトを読む
        guard let header = try? fh.read(upToCount: 92),
              header.count >= 92 else { return nil }

        // "FUJIFILMCCD-RAW " マジックを確認
        let magic = Array("FUJIFILMCCD-RAW ".utf8)
        guard header.prefix(16).elementsEqual(magic) else { return nil }

        // オフセット 84〜87: JPEG セクションの先頭位置（ビッグエンディアン uint32）
        let jpegOffset = Int(header[84]) << 24 | Int(header[85]) << 16
                       | Int(header[86]) << 8  | Int(header[87])
        guard jpegOffset > 92 else { return nil }

        // JPEG 先頭 256KB だけ読む（EXIF サムネイルは通常 100KB 以内）
        try? fh.seek(toOffset: UInt64(jpegOffset))
        guard let jpegHead = try? fh.read(upToCount: 262_144),
              jpegHead.count > 3,
              jpegHead[0] == 0xFF, jpegHead[1] == 0xD8 else { return nil }

        // 部分 JPEG データから ImageSource を作り EXIF サムネイルを取得
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithData(jpegHead as CFData,
                                                    srcOpts as CFDictionary) else { return nil }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) {
            return NSImage(cgImage: cgImage, size: .zero)
        }
        return nil
    }

    /// ARW / CR3 など RAF 以外の RAW 形式用
    nonisolated private static func loadViaCGImageSource(url: URL, maxPixel: Int) -> NSImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
                                                      srcOptions as CFDictionary) else { return nil }

        // 全インデックスで埋め込みサムネイルを探す（フル展開なし）
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        let count = CGImageSourceGetCount(source)
        for i in 0..<count {
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, i,
                                                                 thumbOpts as CFDictionary) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
        }

        // 小ファイル（30MB未満）のみフルデコードへフォールバック
        if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize < 30_000_000 {
            let fullOpts: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0,
                                                                 fullOpts as CFDictionary) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
        }

        return nil
    }

    // MARK: - Full preview

    nonisolated private static func loadFullPreview(url: URL) -> NSImage? {
        // RAF: ヘッダーから埋め込みJPEGをフル読み込み（NSImageがEXIF向きを自動適用）
        if url.pathExtension.uppercased() == "RAF",
           let img = loadRAFFullPreview(url: url) {
            return img
        }

        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
                                                      srcOptions as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        // FromImageIfAbsent = 埋め込みプレビュー優先（RAWフルデコードしない）
        // WithTransform = EXIF向きを適用して縦画像を正しく表示
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 8000,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]
        let count = CGImageSourceGetCount(source)
        var bestImage: CGImage?
        var bestPixels = 0
        for i in 0..<count {
            if let cgImg = CGImageSourceCreateThumbnailAtIndex(source, i,
                                                               thumbOpts as CFDictionary) {
                let pixels = cgImg.width * cgImg.height
                if pixels > bestPixels { bestPixels = pixels; bestImage = cgImg }
            }
        }
        if let cgImg = bestImage { return NSImage(cgImage: cgImg, size: .zero) }

        return NSImage(contentsOf: url)
    }

    /// RAF ヘッダーから埋め込み JPEG をフルサイズで読み込む
    nonisolated private static func loadRAFFullPreview(url: URL) -> NSImage? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        guard let header = try? fh.read(upToCount: 92),
              header.count >= 92 else { return nil }

        let magic = Array("FUJIFILMCCD-RAW ".utf8)
        guard header.prefix(16).elementsEqual(magic) else { return nil }

        // オフセット 84-87: JPEG開始位置、88-91: JPEGサイズ（ビッグエンディアン）
        let jpegOffset = Int(header[84]) << 24 | Int(header[85]) << 16
                       | Int(header[86]) << 8  | Int(header[87])
        let jpegLength = Int(header[88]) << 24 | Int(header[89]) << 16
                       | Int(header[90]) << 8  | Int(header[91])

        guard jpegOffset > 92, jpegLength > 3 else { return nil }

        try? fh.seek(toOffset: UInt64(jpegOffset))
        guard let jpegData = try? fh.read(upToCount: jpegLength),
              jpegData.count > 3,
              jpegData[0] == 0xFF, jpegData[1] == 0xD8 else { return nil }

        // NSImage(data:) は JPEG の EXIF 向きを自動適用する
        return NSImage(data: jpegData)
    }

    // MARK: - Scale

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

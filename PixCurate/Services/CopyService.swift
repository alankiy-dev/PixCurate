import Foundation

struct CopyProgress: Sendable {
    var copied: Int = 0
    var skipped: Int = 0
    var errors: Int = 0

    nonisolated init() {}
}

struct CopyService: Sendable {

    nonisolated init() {}

    /// フィルター済みファイルをコピーする。ログはクロージャで逐次通知する
    /// - sources: 複数コピー元フォルダ。keepStructure=true のときに最適なベースURLを自動選択する。
    nonisolated func copy(
        files: [PhotoFile],
        to dst: URL,
        keepStructure: Bool,
        sources: [SourceSpec],
        dryRun: Bool,
        log: @Sendable (String) -> Void,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) -> CopyProgress {
        var progress = CopyProgress()
        let fm = FileManager.default
        var processed = 0

        for file in files {
            let dstRaw: URL
            if keepStructure, let base = findBase(for: file.rawURL, sources: sources),
               let rel = relativePath(of: file.rawURL, from: base) {
                dstRaw = dst.appendingPathComponent(rel)
            } else {
                dstRaw = dst.appendingPathComponent(file.filename)
            }

            // skip-if-same: XMPの更新日を秒単位で比較
            let xmpDst = dstRaw.deletingPathExtension().appendingPathExtension("xmp")
            if !dryRun,
               let srcMtime = modTime(file.xmpURL),
               let dstMtime = modTime(xmpDst),
               abs(srcMtime.timeIntervalSince(dstMtime)) < 1.0 {
                log("⏭ スキップ（同一）: \(file.filename)")
                progress.skipped += 1
                continue
            }

            let ratingStr = file.rating.map { "★\($0)" } ?? "★?"
            log("\(ratingStr)  \(file.filename)")

            if dryRun {
                let overwrite = fm.fileExists(atPath: dstRaw.path) ? " [上書き]" : ""
                log("  [プレビュー\(overwrite)] → \(dstRaw.path)")
                progress.copied += 1
            } else {
                do {
                    try copyRawAndXMP(rawSrc: file.rawURL, rawDst: dstRaw, fm: fm)
                    log("  ✅ → \(dstRaw.lastPathComponent)")
                    progress.copied += 1
                } catch {
                    log("  ❌ エラー: \(error.localizedDescription)")
                    progress.errors += 1
                }
            }
            processed += 1
            onProgress?(processed)
        }

        return progress
    }

    // MARK: - Private helpers

    private nonisolated func copyRawAndXMP(rawSrc: URL, rawDst: URL, fm: FileManager) throws {
        try fm.createDirectory(
            at: rawDst.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fm.fileExists(atPath: rawDst.path) { try fm.removeItem(at: rawDst) }
        try fm.copyItem(at: rawSrc, to: rawDst)
        if let mtime = modTime(rawSrc) {
            try fm.setAttributes([.modificationDate: mtime], ofItemAtPath: rawDst.path)
        }

        let xmpSrc = rawSrc.deletingPathExtension().appendingPathExtension("xmp")
        let xmpDst = rawDst.deletingPathExtension().appendingPathExtension("xmp")
        guard fm.fileExists(atPath: xmpSrc.path) else { return }
        if fm.fileExists(atPath: xmpDst.path) { try fm.removeItem(at: xmpDst) }
        try fm.copyItem(at: xmpSrc, to: xmpDst)
        if let mtime = modTime(xmpSrc) {
            try fm.setAttributes([.modificationDate: mtime], ofItemAtPath: xmpDst.path)
        }
    }

    private nonisolated func modTime(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// sources の中からファイルに最も近い（最長プレフィックスの）ソースURLを返す
    private nonisolated func findBase(for url: URL, sources: [SourceSpec]) -> URL? {
        let filePath = url.resolvingSymlinksInPath().path
        var best: (URL, Int)? = nil
        for spec in sources {
            let basePath = spec.url.resolvingSymlinksInPath().path
            let baseWithSlash = basePath.hasSuffix("/") ? basePath : basePath + "/"
            if filePath.hasPrefix(baseWithSlash) {
                let len = baseWithSlash.count
                if best == nil || len > best!.1 { best = (spec.url, len) }
            }
        }
        return best?.0
    }

    private nonisolated func relativePath(of url: URL, from base: URL) -> String? {
        let urlPath = url.resolvingSymlinksInPath().path
        let basePath = base.resolvingSymlinksInPath().path
        let baseWithSlash = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard urlPath.hasPrefix(baseWithSlash) else { return nil }
        return String(urlPath.dropFirst(baseWithSlash.count))
    }
}

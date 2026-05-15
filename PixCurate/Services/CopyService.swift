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
    nonisolated func copy(
        files: [PhotoFile],
        to dst: URL,
        keepStructure: Bool,
        baseURL: URL,
        dryRun: Bool,
        log: @Sendable (String) -> Void
    ) -> CopyProgress {
        var progress = CopyProgress()
        let fm = FileManager.default

        for file in files {
            let dstRaw: URL
            if keepStructure, let rel = relativePath(of: file.rawURL, from: baseURL) {
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

    private nonisolated func relativePath(of url: URL, from base: URL) -> String? {
        let urlPath = url.resolvingSymlinksInPath().path
        let basePath = base.resolvingSymlinksInPath().path
        let baseWithSlash = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard urlPath.hasPrefix(baseWithSlash) else { return nil }
        return String(urlPath.dropFirst(baseWithSlash.count))
    }
}

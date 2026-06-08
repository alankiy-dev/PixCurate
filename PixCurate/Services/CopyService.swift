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
        // ソースフォルダの一覧を使い回す（同名ファイル探索のたびに再列挙しない）
        var dirCache: [String: [URL]] = [:]

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
                // 同名で一緒にコピーされる関連ファイル（XMP/JPEG等）も表示
                let companions = companionFiles(for: file.rawURL, fm: fm, cache: &dirCache)
                    .map(\.lastPathComponent)
                    .filter { $0 != file.rawURL.lastPathComponent }
                if !companions.isEmpty {
                    log("    + 同名ファイル: \(companions.joined(separator: ", "))")
                }
                progress.copied += 1
            } else {
                do {
                    try copyCompanions(rawSrc: file.rawURL, rawDst: dstRaw, fm: fm, cache: &dirCache)
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

    /// RAW 本体と、同フォルダにある同名（拡張子は問わない）ファイルをすべてコピーする。
    /// 例: DSCF5364.RAF / .xmp / .jpg をまとめてコピー先へ複製する。
    private nonisolated func copyCompanions(rawSrc: URL, rawDst: URL, fm: FileManager,
                                            cache: inout [String: [URL]]) throws {
        let dstDir = rawDst.deletingLastPathComponent()
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)

        // 同名ファイル一覧（見つからなければ RAW 本体だけは必ずコピー）
        var sources = companionFiles(for: rawSrc, fm: fm, cache: &cache)
        if sources.isEmpty { sources = [rawSrc] }

        for src in sources {
            let dstURL = dstDir.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dstURL.path) { try fm.removeItem(at: dstURL) }
            try fm.copyItem(at: src, to: dstURL)
            if let mtime = modTime(src) {
                try fm.setAttributes([.modificationDate: mtime], ofItemAtPath: dstURL.path)
            }
        }
    }

    /// rawSrc と同じフォルダにある、ファイル名（拡張子を除く）が一致するファイル一覧。
    /// rawSrc 自身も含む。ディレクトリ列挙結果は cache で使い回す。
    private nonisolated func companionFiles(for rawSrc: URL, fm: FileManager,
                                            cache: inout [String: [URL]]) -> [URL] {
        let dir = rawSrc.deletingLastPathComponent()
        let entries: [URL]
        if let cached = cache[dir.path] {
            entries = cached
        } else {
            entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles])) ?? []
            cache[dir.path] = entries
        }
        let stem = rawSrc.deletingPathExtension().lastPathComponent
        return entries.filter { $0.deletingPathExtension().lastPathComponent == stem }
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

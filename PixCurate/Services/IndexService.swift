import Foundation

// MARK: - IndexService

enum IndexService {

    struct ScanResult: Sendable {
        var loaded: Int       // DBから即ロードした件数
        var added: Int        // 新規インデックス
        var updated: Int      // XMP変更で更新
        var removed: Int      // ディスクから消えた件数
    }

    /// 最終スキャン日時（フォルダ更新日時による高速スキャンの基準）。
    /// これより後に更新されたフォルダだけを実際に読み直す。
    nonisolated static var lastScanDate: Date {
        get { (UserDefaults.standard.object(forKey: "pixcurate.lastScanDate") as? Date) ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "pixcurate.lastScanDate") }
    }

    // MARK: - DBから即ロード

    /// 拡大表示ウィンドウ用：指定URLファイルの評価をXMPから読み込む
    nonisolated static func loadRating(for rawURL: URL) -> Int? {
        let xmpURL = rawURL.deletingPathExtension().appendingPathExtension("xmp")
        let r = XMPService.readRating(xmpURL: xmpURL)
        return r == 0 ? nil : r
    }

    nonisolated static func loadFromDB(folder: URL) -> [PhotoFile] {
        let rows = DatabaseService.shared.loadFiles(under: folder)
        let locStore = LocationStore.shared
        return rows.map { row in
            var file = row.toPhotoFile()
            if let lid = file.locationId {
                file.locationPath = locStore.buildLocationPath(for: lid)
            }
            return file
        }
    }

    /// 複数ソースから DB をロード（重複除去・recursive/非recursive 対応）
    nonisolated static func loadFromDB(sources: [SourceSpec]) -> [PhotoFile] {
        guard !sources.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [PhotoFile] = []
        for spec in sources {
            let rows = DatabaseService.shared.loadFiles(under: spec.url)
            let locStore = LocationStore.shared
            for row in rows {
                guard seen.insert(row.path).inserted else { continue }
                // 非recursive の場合は直下のファイルのみ
                if !spec.isRecursive {
                    let parentPath = URL(fileURLWithPath: row.path)
                        .deletingLastPathComponent().path
                    guard parentPath == spec.url.path else { continue }
                }
                var file = row.toPhotoFile()
                if let lid = file.locationId {
                    file.locationPath = locStore.buildLocationPath(for: lid)
                }
                result.append(file)
            }
        }
        return result
    }

    // MARK: - フルスキャン＋DB同期（複数ソース）

    /// 複数ソースをまとめてスキャンする（recursive/非recursive 対応）
    nonisolated static func fullScan(
        sources: [SourceSpec],
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) -> (files: [PhotoFile], result: ScanResult) {
        guard !sources.isEmpty else {
            return ([], ScanResult(loaded: 0, added: 0, updated: 0, removed: 0))
        }

        let rawExtensions: Set<String> = ["raf", "arw", "cr3", "cr2", "jpg", "jpeg"]
        let fm = FileManager.default
        var diskPaths = Set<String>()
        var allURLs: [URL] = []

        for spec in sources {
            let urls = collectURLs(in: spec, extensions: rawExtensions, fm: fm)
            for url in urls where diskPaths.insert(url.path).inserted {
                allURLs.append(url)
            }
        }

        let total = allURLs.count

        // XMP更新日時を収集
        var xmpDates: [String: Date] = [:]
        for url in allURLs {
            let xmp = url.deletingPathExtension().appendingPathExtension("xmp")
            if let attr = try? fm.attributesOfItem(atPath: xmp.path),
               let mod = attr[.modificationDate] as? Date {
                xmpDates[url.path] = mod
            }
        }

        // DBから現在のデータを収集（全ソース分）
        var dbDict: [String: DBFileRow] = [:]
        var allIndexed = Set<String>()
        for spec in sources {
            let rows = DatabaseService.shared.loadFiles(under: spec.url)
            for row in rows {
                dbDict[row.path] = row
                if spec.isRecursive {
                    allIndexed.insert(row.path)
                } else {
                    let parent = URL(fileURLWithPath: row.path).deletingLastPathComponent().path
                    if parent == spec.url.path { allIndexed.insert(row.path) }
                }
            }
        }

        var changedPaths = Set<String>()
        for spec in sources {
            changedPaths.formUnion(
                DatabaseService.shared.changedPaths(under: spec.url, currentXmpDates: xmpDates)
            )
        }

        let locStore = LocationStore.shared
        var scanned: [PhotoFile] = []
        var added = 0
        var updated = 0

        for (i, fileURL) in allURLs.enumerated() {
            progress(i + 1, total)
            let path = fileURL.path
            let isNew = dbDict[path] == nil
            let isChanged = changedPaths.contains(path) || isNew

            if isChanged {
                var file = PhotoFile(rawURL: fileURL)
                let xmpURL = file.xmpURL
                if fm.fileExists(atPath: xmpURL.path) {
                    file.rating       = XMPService.readRating(xmpURL: xmpURL)
                    file.tags         = XMPTagService.readTags(xmpURL: xmpURL)
                    file.locationPath = XMPLocationService.readLocation(xmpURL: xmpURL)
                    file.colorLabel   = XMPService.readColorLabel(xmpURL: xmpURL)
                }
                file.shotDate = EXIFService.readShotDate(url: fileURL)
                    ?? (try? fm.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
                if let lp = file.locationPath {
                    file.locationId = locStore.match(path: lp)
                }
                let xmpMod = xmpDates[path]
                file.xmpModifiedAt = xmpMod
                DatabaseService.shared.upsert(file, xmpModifiedAt: xmpMod)
                scanned.append(file)
                if isNew { added += 1 } else { updated += 1 }
            } else if let row = dbDict[path] {
                var file = row.toPhotoFile()
                if let lid = file.locationId {
                    file.locationPath = locStore.buildLocationPath(for: lid)
                }
                scanned.append(file)
            } else {
                scanned.append(PhotoFile(rawURL: fileURL))
            }
        }

        // DBにあってディスクにないファイルを削除
        let stale = allIndexed.subtracting(diskPaths)
        for path in stale { DatabaseService.shared.delete(path: path) }

        scanned.sort { $0.filename < $1.filename }

        let result = ScanResult(loaded: 0, added: added, updated: updated, removed: stale.count)
        return (scanned, result)
    }

    // MARK: - 高速スキャン（フォルダ更新日時で枝刈り）

    /// `since` より後に更新されたフォルダのファイルだけを実際に読み直す差分スキャン。
    /// 変更のないフォルダは XMP を stat せず DB の内容をそのまま流用するため、
    /// 大量ファイル（外付け/NAS）でも「触ったフォルダ分」だけの処理で済み、大幅に高速化する。
    ///
    /// - Note: 判定はフォルダの更新日時。ファイルの追加・削除・リネームや、
    ///   一時ファイル＋リネーム方式で保存されるXMP（Adobe系など）はフォルダ日時が変わるため検出できる。
    ///   ごく稀に「XMPをその場上書き（リネームなし）」する場合は取りこぼす可能性があるため、
    ///   確実に反映したいときは「完全再スキャン」（since=distantPast）や DB再構築 を使う。
    nonisolated static func fastScan(
        sources: [SourceSpec],
        since: Date,
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) -> (files: [PhotoFile], result: ScanResult) {
        guard !sources.isEmpty else {
            return ([], ScanResult(loaded: 0, added: 0, updated: 0, removed: 0))
        }
        let rawExtensions: Set<String> = ["raf", "arw", "cr3", "cr2", "jpg", "jpeg"]
        let fm = FileManager.default
        let locStore = LocationStore.shared

        // ベース：DBの全行（変更のないフォルダ分はこれをそのまま使う）
        var byPath: [String: PhotoFile] = [:]
        for f in loadFromDB(sources: sources) { byPath[f.rawURL.path] = f }

        // DBに登録済みのフォルダ集合。ここに無いフォルダ（新規追加したコピー元など）は
        // 更新日時が古くても必ずスキャンする（枝刈り対象にしない）。
        var dbDirs = Set<String>()
        for path in byPath.keys {
            dbDirs.insert(URL(fileURLWithPath: path).deletingLastPathComponent().path)
        }

        // ディスク上のRAW一覧（重複除去）
        var diskURLs: [URL] = []
        var seenDisk = Set<String>()
        for spec in sources {
            for url in collectURLs(in: spec, extensions: rawExtensions, fm: fm)
            where seenDisk.insert(url.path).inserted {
                diskURLs.append(url)
            }
        }

        // フォルダ更新日時のキャッシュ（1フォルダ1回だけ stat）
        var dirMtimeCache: [String: Bool] = [:]
        func dirChanged(_ dir: String) -> Bool {
            if let c = dirMtimeCache[dir] { return c }
            // DB未登録のフォルダ（新規追加コピー元など）は日時に関わらず必ずスキャン
            let unknown = !dbDirs.contains(dir)
            let mod = ((try? fm.attributesOfItem(atPath: dir))?[.modificationDate] as? Date) ?? .distantPast
            let changed = unknown || mod > since
            dirMtimeCache[dir] = changed
            return changed
        }

        let total = diskURLs.count
        var added = 0, updated = 0
        var changedDirs = Set<String>()
        var seenInChangedDirs = Set<String>()

        for (i, url) in diskURLs.enumerated() {
            progress(i + 1, total)
            let path = url.path
            let dir = url.deletingLastPathComponent().path
            // 変更のないフォルダ → DB行をそのまま流用（XMPを読まない）
            guard dirChanged(dir) else { continue }
            changedDirs.insert(dir)
            seenInChangedDirs.insert(path)

            let isNew = byPath[path] == nil
            var file = PhotoFile(rawURL: url)
            let xmpURL = file.xmpURL
            var xmpMod: Date? = nil
            if fm.fileExists(atPath: xmpURL.path) {
                file.rating       = XMPService.readRating(xmpURL: xmpURL)
                file.tags         = XMPTagService.readTags(xmpURL: xmpURL)
                file.locationPath = XMPLocationService.readLocation(xmpURL: xmpURL)
                file.colorLabel   = XMPService.readColorLabel(xmpURL: xmpURL)
                xmpMod = (try? fm.attributesOfItem(atPath: xmpURL.path))?[.modificationDate] as? Date
            }
            file.shotDate = EXIFService.readShotDate(url: url)
                ?? (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            if let lp = file.locationPath { file.locationId = locStore.match(path: lp) }
            file.xmpModifiedAt = xmpMod
            DatabaseService.shared.upsert(file, xmpModifiedAt: xmpMod)
            byPath[path] = file
            if isNew { added += 1 } else { updated += 1 }
        }

        // 変更のあったフォルダ内で、ディスクから消えたファイルをDBから削除
        var removed = 0
        for path in Array(byPath.keys) {
            let dir = URL(fileURLWithPath: path).deletingLastPathComponent().path
            if changedDirs.contains(dir), !seenInChangedDirs.contains(path) {
                DatabaseService.shared.delete(path: path)
                byPath[path] = nil
                removed += 1
            }
        }

        let scanned = byPath.values.sorted { $0.filename < $1.filename }
        return (scanned, ScanResult(loaded: 0, added: added, updated: updated, removed: removed))
    }

    /// 1フォルダ内のRAWファイルURLを収集（recursive/非recursive 対応）
    private nonisolated static func collectURLs(
        in spec: SourceSpec,
        extensions: Set<String>,
        fm: FileManager
    ) -> [URL] {
        if spec.isRecursive {
            var result: [URL] = []
            guard let enumerator = fm.enumerator(
                at: spec.url,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            while let url = enumerator.nextObject() as? URL {
                if extensions.contains(url.pathExtension.lowercased()) { result.append(url) }
            }
            return result
        } else {
            let contents = (try? fm.contentsOfDirectory(
                at: spec.url,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return contents.filter { extensions.contains($0.pathExtension.lowercased()) }
        }
    }

    // MARK: - フルスキャン＋DB同期（単一フォルダ・後方互換）

    nonisolated static func fullScan(
        folder: URL,
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) -> (files: [PhotoFile], result: ScanResult) {

        let rawExtensions: Set<String> = ["raf", "arw", "cr3", "cr2", "jpg", "jpeg"]
        let fm = FileManager.default
        let locStore = LocationStore.shared
        var diskPaths = Set<String>()

        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return ([], ScanResult(loaded: 0, added: 0, updated: 0, removed: 0)) }

        var allURLs: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard rawExtensions.contains(url.pathExtension.lowercased()) else { continue }
            allURLs.append(url)
            diskPaths.insert(url.path)
        }

        let total = allURLs.count

        // XMP更新日時を収集
        var xmpDates: [String: Date] = [:]
        for url in allURLs {
            let xmp = url.deletingPathExtension().appendingPathExtension("xmp")
            if let attr = try? fm.attributesOfItem(atPath: xmp.path),
               let mod = attr[.modificationDate] as? Date {
                xmpDates[url.path] = mod
            }
        }

        // DBから現在のデータを辞書で取得
        let dbRows = DatabaseService.shared.loadFiles(under: folder)
        var dbDict: [String: DBFileRow] = [:]
        for row in dbRows { dbDict[row.path] = row }

        let changedPaths = DatabaseService.shared.changedPaths(under: folder, currentXmpDates: xmpDates)

        var scanned: [PhotoFile] = []
        var added = 0
        var updated = 0

        for (i, fileURL) in allURLs.enumerated() {
            progress(i + 1, total)
            let path = fileURL.path
            let isNew = dbDict[path] == nil
            let isChanged = changedPaths.contains(path) || isNew

            if isChanged {
                var file = PhotoFile(rawURL: fileURL)
                let xmpURL = file.xmpURL
                if fm.fileExists(atPath: xmpURL.path) {
                    file.rating       = XMPService.readRating(xmpURL: xmpURL)
                    file.tags         = XMPTagService.readTags(xmpURL: xmpURL)
                    file.locationPath = XMPLocationService.readLocation(xmpURL: xmpURL)
                    file.colorLabel   = XMPService.readColorLabel(xmpURL: xmpURL)
                }
                file.shotDate = EXIFService.readShotDate(url: fileURL)
                    ?? (try? fm.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
                if let lp = file.locationPath {
                    file.locationId = locStore.match(path: lp)
                }
                let xmpMod = xmpDates[path]
                file.xmpModifiedAt = xmpMod
                DatabaseService.shared.upsert(file, xmpModifiedAt: xmpMod)
                scanned.append(file)
                if isNew { added += 1 } else { updated += 1 }
            } else if let row = dbDict[path] {
                var file = row.toPhotoFile()
                if let lid = file.locationId {
                    file.locationPath = locStore.buildLocationPath(for: lid)
                }
                scanned.append(file)
            } else {
                scanned.append(PhotoFile(rawURL: fileURL))
            }
        }

        // DBにあってディスクにないファイルを削除
        let indexed = DatabaseService.shared.indexedPaths(under: folder)
        let stale = indexed.subtracting(diskPaths)
        for path in stale { DatabaseService.shared.delete(path: path) }

        scanned.sort { $0.filename < $1.filename }

        let result = ScanResult(loaded: 0, added: added, updated: updated, removed: stale.count)
        return (scanned, result)
    }

    // MARK: - 差分スキャン（起動後の高速更新）

    nonisolated static func incrementalScan(
        folder: URL,
        existing: inout [PhotoFile]
    ) -> ScanResult {
        let rawExtensions: Set<String> = ["raf", "arw", "cr3", "cr2", "jpg", "jpeg"]
        let fm = FileManager.default
        let locStore = LocationStore.shared
        var diskPaths = Set<String>()
        var xmpDates: [String: Date] = [:]

        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return ScanResult(loaded: 0, added: 0, updated: 0, removed: 0) }

        var allURLs: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard rawExtensions.contains(url.pathExtension.lowercased()) else { continue }
            allURLs.append(url)
            diskPaths.insert(url.path)
            let xmp = url.deletingPathExtension().appendingPathExtension("xmp")
            if let attr = try? fm.attributesOfItem(atPath: xmp.path),
               let mod = attr[.modificationDate] as? Date {
                xmpDates[url.path] = mod
            }
        }

        // DB未登録のパスも検出
        let indexed = DatabaseService.shared.indexedPaths(under: folder)
        let changedPaths = DatabaseService.shared.changedPaths(under: folder, currentXmpDates: xmpDates)
        let newPaths = diskPaths.subtracting(indexed)
        let toProcess = changedPaths.union(newPaths)

        var added = 0, updated = 0

        for fileURL in allURLs where toProcess.contains(fileURL.path) {
            let path = fileURL.path
            var file = PhotoFile(rawURL: fileURL)
            let xmpURL = file.xmpURL
            if fm.fileExists(atPath: xmpURL.path) {
                file.rating       = XMPService.readRating(xmpURL: xmpURL)
                file.tags         = XMPTagService.readTags(xmpURL: xmpURL)
                file.locationPath = XMPLocationService.readLocation(xmpURL: xmpURL)
                file.colorLabel   = XMPService.readColorLabel(xmpURL: xmpURL)
            }
            file.shotDate = EXIFService.readShotDate(url: fileURL)
                ?? (try? fm.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
            if let lp = file.locationPath {
                file.locationId = locStore.match(path: lp)
            }
            let xmpMod = xmpDates[path]
            file.xmpModifiedAt = xmpMod
            DatabaseService.shared.upsert(file, xmpModifiedAt: xmpMod)

            if let idx = existing.firstIndex(where: { $0.rawURL == fileURL }) {
                existing[idx] = file
                updated += 1
            } else {
                existing.append(file)
                added += 1
            }
        }

        // 消えたファイルを除去
        let stale = indexed.subtracting(diskPaths)
        for path in stale { DatabaseService.shared.delete(path: path) }
        existing.removeAll { stale.contains($0.rawURL.path) }
        existing.sort { $0.filename < $1.filename }

        return ScanResult(loaded: 0, added: added, updated: updated, removed: stale.count)
    }
}

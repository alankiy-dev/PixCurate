import Foundation

// MARK: - IndexService

enum IndexService {

    struct ScanResult: Sendable {
        var loaded: Int       // DBから即ロードした件数
        var added: Int        // 新規インデックス
        var updated: Int      // XMP変更で更新
        var removed: Int      // ディスクから消えた件数
    }

    // MARK: - DBから即ロード

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

    // MARK: - フルスキャン＋DB同期

    nonisolated static func fullScan(
        folder: URL,
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) -> (files: [PhotoFile], result: ScanResult) {

        let rawExtensions: Set<String> = ["raf", "arw", "cr3"]
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
        let rawExtensions: Set<String> = ["raf", "arw", "cr3"]
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

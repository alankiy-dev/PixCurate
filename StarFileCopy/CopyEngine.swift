import Foundation
import Combine

// MARK: - Result types

struct CopyResult {
    var copied: Int = 0
    var skippedDate: Int = 0
    var skippedRating: Int = 0
    var skippedSame: Int = 0    // ← 追加
    var noXmp: Int = 0
    var errors: Int = 0
}

// MARK: - CopyEngine

class CopyEngine: ObservableObject {
    @Published private var _unused: Bool = false
    // 対応拡張子
    private let targetExtensions: Set<String> = [
        "cr2","cr3",          // Canon
        "arw","srf",          // Sony
        "nef","nrw",          // Nikon
        "dng",                // Adobe DNG
        "rw2",                // Panasonic
        "orf",                // Olympus
        "raf",                // Fujifilm
        "pef",                // Pentax
        "srw",                // Samsung
        "3fr",                // Hasselblad
        "jpg","jpeg",         // JPEG
        "tif","tiff"          // TIFF
    ]
    
    // MARK: - Public run method
    
    /// ログをクロージャで都度通知しながらコピーを実行する
    func run(
        src: URL,
        dst: URL,
        since: Date,
        minRating: Int,
        maxRating: Int,
        keepStructure: Bool,
        dryRun: Bool,
        log: @escaping (String) -> Void
    ) -> CopyResult {
        
        var result = CopyResult()
        
        // exiftool の存在確認
        let exiftoolPath = findExiftool()
        guard let exiftool = exiftoolPath else {
            log("❌ exiftool が見つかりません。")
            log("   ターミナルで: brew install exiftool")
            return result
        }
        
        let sinceDay = Calendar.current.startOfDay(for: since)
        let fm = FileManager.default
        
        // 対象ファイルを収集
        guard let enumerator = fm.enumerator(
            at: src,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            log("❌ フォルダを読み込めません: \(src.path)")
            return result
        }
        
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if targetExtensions.contains(ext) {
                files.append(fileURL)
            }
        }
        
        log("🔎 検索対象: \(files.count) ファイル")
        
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let xmpURL = file.deletingPathExtension().appendingPathExtension("xmp")
            
            // .xmp が存在するか
            guard fm.fileExists(atPath: xmpURL.path) else {
                result.noXmp += 1
                continue
            }
            
            // .xmp の更新日フィルター
            guard let xmpDate = modificationDate(of: xmpURL),
                  Calendar.current.startOfDay(for: xmpDate) >= sinceDay else {
                result.skippedDate += 1
                continue
            }
            
            // レーティング取得
            guard let rating = getRating(xmpURL: xmpURL, exiftool: exiftool),
                  rating >= minRating, rating <= maxRating else {
                result.skippedRating += 1
                continue
            }
            
            // コピー先パスを決定
            let dstFile: URL
            if keepStructure, let rel = relativePath(of: file, from: src) {
                dstFile = dst.appendingPathComponent(rel)
            } else {
                dstFile = dst.appendingPathComponent(file.lastPathComponent)
            }
            
            let xmpDateStr = dateString(xmpDate)
            log("★\(rating)  \(file.lastPathComponent)  (.xmp更新: \(xmpDateStr))")
            
            if dryRun {
                let dstXmp = dstFile.deletingPathExtension().appendingPathExtension("xmp")
                if let srcMtime = modificationDate(of: xmpURL),
                   let dstMtime = modificationDate(of: dstXmp),
                   abs(srcMtime.timeIntervalSince(dstMtime)) < 1.0 {
                    log("  ⏭  スキップ予定（同一）: \(file.lastPathComponent)")
                } else {
                    let mark = fm.fileExists(atPath: dstFile.path) ? " [上書き]" : ""
                    log("  [プレビュー\(mark)] → \(dstFile.path)")
                    result.copied += 1
                }
            } else {
                // 秒単位で .xmp 更新日を比較してスキップ判定
                let dstXmp = dstFile.deletingPathExtension().appendingPathExtension("xmp")
                if let srcMtime = modificationDate(of: xmpURL),
                   let dstMtime = modificationDate(of: dstXmp),
                   abs(srcMtime.timeIntervalSince(dstMtime)) < 1.0 {
                    log("  ⏭  スキップ（同一）: \(file.lastPathComponent)")
                    result.skippedSame += 1
                    continue
                }
                do {
                    try copyFile(src: file, dst: dstFile, fm: fm)
                    result.copied += 1
                } catch {
                    log("  ❌ エラー: \(error.localizedDescription)")
                    result.errors += 1
                }
            }
        }
        
        return result
    }
    
    // MARK: - Private helpers
    
    private func findExiftool() -> String? {
        let candidates = [
            "/opt/homebrew/bin/exiftool",   // Apple Silicon
            "/usr/local/bin/exiftool",      // Intel Mac
            "/usr/bin/exiftool"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }
    
    private func getRating(xmpURL: URL, exiftool: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exiftool)
        process.arguments = ["-j", "-XMP:Rating", xmpURL.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = json.first,
              let rating = first["Rating"] as? Int,
              rating > 0 else {
            return nil
        }
        return rating
    }
    
    private func modificationDate(of url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
    
    private func relativePath(of url: URL, from base: URL) -> String? {
        let urlPath = url.standardized.path
        let basePath = base.standardized.path + "/"
        guard urlPath.hasPrefix(basePath) else { return nil }
        return String(urlPath.dropFirst(basePath.count))
    }
    
    private func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
    
    private func copyFile(src: URL, dst: URL, fm: FileManager) throws {
        // 親フォルダを作成
        try fm.createDirectory(
            at: dst.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // 上書きコピー
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
        // 元ファイルのタイムスタンプをコピー先に反映
        if let mtime = modificationDate(of: src) {
            try fm.setAttributes([.modificationDate: mtime], ofItemAtPath: dst.path)
        }
        
        // .xmp も上書きコピー＋タイムスタンプ復元
        let xmpSrc = src.deletingPathExtension().appendingPathExtension("xmp")
        let xmpDst = dst.deletingPathExtension().appendingPathExtension("xmp")
        if fm.fileExists(atPath: xmpSrc.path) {
            if fm.fileExists(atPath: xmpDst.path) {
                try fm.removeItem(at: xmpDst)
            }
            try fm.copyItem(at: xmpSrc, to: xmpDst)
            // .xmp のタイムスタンプも復元
            if let xmpMtime = modificationDate(of: xmpSrc) {
                try fm.setAttributes([.modificationDate: xmpMtime], ofItemAtPath: xmpDst.path)
            }
        }
    }
}


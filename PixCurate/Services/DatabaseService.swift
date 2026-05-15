import Foundation
import SQLite3

// MARK: - SQLite3 thin wrapper

// SQLITE_TRANSIENT is a C macro; define it manually for Swift
private let SQLITE_TRANSIENT_FN = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DatabaseService: @unchecked Sendable {
    static let shared = DatabaseService()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "pixcurate.db", qos: .userInitiated)

    private init() {
        openDatabase()
        createTables()
    }

    // MARK: - Setup

    private var dbURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PixCurate")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("index.sqlite")
    }

    private func openDatabase() {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("DB open error: \(String(cString: sqlite3_errmsg(db)))")
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
    }

    private func createTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS files (
                file_path        TEXT PRIMARY KEY,
                file_name        TEXT NOT NULL,
                shot_date        TEXT,
                rating           INTEGER,
                location_id      TEXT,
                xmp_modified_at  TEXT,
                indexed_at       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
            );
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS file_tags (
                file_path TEXT NOT NULL REFERENCES files(file_path) ON DELETE CASCADE,
                tag_name  TEXT NOT NULL,
                PRIMARY KEY (file_path, tag_name)
            );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_files_rating    ON files(rating);")
        exec("CREATE INDEX IF NOT EXISTS idx_files_shot_date ON files(shot_date);")
        exec("CREATE INDEX IF NOT EXISTS idx_file_tags_path  ON file_tags(file_path);")
        exec("CREATE INDEX IF NOT EXISTS idx_file_tags_tag   ON file_tags(tag_name);")
        exec("PRAGMA foreign_keys = ON;")
    }

    // MARK: - Upsert

    nonisolated func upsert(_ file: PhotoFile, xmpModifiedAt: Date?) {
        queue.sync {
            let path   = file.rawURL.path
            let name   = file.filename
            let date   = file.shotDate.map { iso($0) }
            let rating = file.rating
            let locId  = file.locationId?.uuidString
            let xmpMod = xmpModifiedAt.map { iso($0) }

            exec("""
                INSERT INTO files(file_path, file_name, shot_date, rating, location_id, xmp_modified_at)
                VALUES (?,?,?,?,?,?)
                ON CONFLICT(file_path) DO UPDATE SET
                  file_name       = excluded.file_name,
                  shot_date       = excluded.shot_date,
                  rating          = excluded.rating,
                  location_id     = excluded.location_id,
                  xmp_modified_at = excluded.xmp_modified_at,
                  indexed_at      = strftime('%Y-%m-%dT%H:%M:%SZ','now');
            """, bindings: [path, name, date as Any, rating as Any, locId as Any, xmpMod as Any])

            exec("DELETE FROM file_tags WHERE file_path = ?;", bindings: [path])
            for tag in file.tags {
                exec("INSERT OR IGNORE INTO file_tags(file_path, tag_name) VALUES (?,?);",
                     bindings: [path, tag])
            }
        }
    }

    nonisolated func delete(path: String) {
        queue.sync { exec("DELETE FROM files WHERE file_path = ?;", bindings: [path]) }
    }

    // MARK: - Query

    /// folder配下の全ファイルをDBから取得
    nonisolated func loadFiles(under folder: URL) -> [DBFileRow] {
        queue.sync {
            let prefix = folder.path + "/"
            var rows: [DBFileRow] = []

            let sql = """
                SELECT f.file_path, f.file_name, f.shot_date, f.rating,
                       f.location_id, f.xmp_modified_at,
                       GROUP_CONCAT(t.tag_name, '\t') AS tags
                FROM files f
                LEFT JOIN file_tags t ON t.file_path = f.file_path
                WHERE f.file_path LIKE ? ESCAPE '\\'
                GROUP BY f.file_path
                ORDER BY f.file_name;
            """
            let pattern = escapeLike(prefix) + "%"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT_FN)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    rows.append(DBFileRow(stmt: stmt!))
                }
            }
            sqlite3_finalize(stmt)
            return rows
        }
    }

    /// XMPが変更されているパスのみ返す
    nonisolated func changedPaths(under folder: URL, currentXmpDates: [String: Date]) -> Set<String> {
        queue.sync {
            let prefix = folder.path + "/"
            var result = Set<String>()
            let sql = "SELECT file_path, xmp_modified_at FROM files WHERE file_path LIKE ? ESCAPE '\\';"
            let pattern = escapeLike(prefix) + "%"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT_FN)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let path = String(cString: sqlite3_column_text(stmt, 0))
                    let stored = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                    let current = currentXmpDates[path].map { iso($0) }
                    if stored != current { result.insert(path) }
                }
            }
            sqlite3_finalize(stmt)
            // DB未登録のパスも変更扱い
            let known = Set(result)
            for path in currentXmpDates.keys where !known.contains(path) && path.hasPrefix(prefix) {
                result.insert(path)
            }
            return result
        }
    }

    nonisolated func indexedPaths(under folder: URL) -> Set<String> {
        queue.sync {
            let prefix = folder.path + "/"
            var result = Set<String>()
            let sql = "SELECT file_path FROM files WHERE file_path LIKE ? ESCAPE '\\';"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, escapeLike(prefix) + "%", -1, SQLITE_TRANSIENT_FN)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    result.insert(String(cString: sqlite3_column_text(stmt, 0)))
                }
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    nonisolated func fileCount(under folder: URL) -> Int {
        queue.sync {
            let prefix = folder.path + "/"
            var stmt: OpaquePointer?
            var count = 0
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM files WHERE file_path LIKE ? ESCAPE '\\'",
                                   -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, escapeLike(prefix) + "%", -1, SQLITE_TRANSIENT_FN)
                if sqlite3_step(stmt) == SQLITE_ROW { count = Int(sqlite3_column_int(stmt, 0)) }
            }
            sqlite3_finalize(stmt)
            return count
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func exec(_ sql: String, bindings: [Any?] = []) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        for (i, val) in bindings.enumerated() {
            let col = Int32(i + 1)
            switch val {
            case let s as String: sqlite3_bind_text(stmt, col, s, -1, SQLITE_TRANSIENT_FN)
            case let n as Int:    sqlite3_bind_int64(stmt, col, Int64(n))
            case nil:             sqlite3_bind_null(stmt, col)
            default:              sqlite3_bind_null(stmt, col)
            }
        }
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "%", with: "\\%")
         .replacingOccurrences(of: "_", with: "\\_")
    }
}

// MARK: - Row

struct DBFileRow: Sendable {
    let path: String
    let name: String
    let shotDate: Date?
    let rating: Int?
    let locationId: UUID?
    let xmpModifiedAt: Date?
    let tags: [String]

    init(stmt: OpaquePointer) {
        path     = String(cString: sqlite3_column_text(stmt, 0))
        name     = String(cString: sqlite3_column_text(stmt, 1))
        let fmt  = ISO8601DateFormatter()
        shotDate = sqlite3_column_text(stmt, 2).flatMap { fmt.date(from: String(cString: $0)) }
        rating   = sqlite3_column_type(stmt, 3) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 3)) : nil
        locationId = sqlite3_column_text(stmt, 4).flatMap { UUID(uuidString: String(cString: $0)) }
        xmpModifiedAt = sqlite3_column_text(stmt, 5).flatMap { fmt.date(from: String(cString: $0)) }
        let tagStr = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
        tags = tagStr.isEmpty ? [] : tagStr.components(separatedBy: "\t")
    }

    nonisolated func toPhotoFile() -> PhotoFile {
        var f = PhotoFile(rawURL: URL(fileURLWithPath: path))
        f.rating         = rating
        f.shotDate       = shotDate
        f.tags           = tags
        f.locationId     = locationId
        f.xmpModifiedAt  = xmpModifiedAt
        return f
    }
}

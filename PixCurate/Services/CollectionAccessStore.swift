import Foundation

/// コレクションに登録されたファイルのフォルダへ security-scoped bookmark を保持する。
///
/// コピー元フォルダの構成（追加・削除・有効/無効）に依存せず、コレクションの
/// 実ファイル（サムネイル生成・拡大表示で必要）へアクセスできるようにするための仕組み。
///
/// - コレクション追加時に、対象ファイルの親フォルダ単位で bookmark を保存する
///   （その時点ではコピー元 scope 内にあるためアクセス可能で bookmark を作成できる）。
/// - 起動時に保存済み bookmark を解決して startAccessingSecurityScopedResource する。
final class CollectionAccessStore: @unchecked Sendable {
    static let shared = CollectionAccessStore()

    private let key = "pixcurate.collectionFolderBookmarks"
    private let lock = NSLock()
    /// folderPath -> bookmarkData
    private var bookmarks: [String: Data] = [:]
    /// アクセス中の URL（stopAccessing 用に保持）
    private var accessing: [String: URL] = [:]

    private init() { loadFromDefaults() }

    private func loadFromDefaults() {
        if let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] {
            bookmarks = dict
        }
    }

    private func saveToDefaults() {
        UserDefaults.standard.set(bookmarks, forKey: key)
    }

    /// 起動時に呼ぶ。保存済み bookmark を解決してアクセスを開始する。
    func resolveAndStartAccessing() {
        lock.lock(); let entries = bookmarks; lock.unlock()
        var refreshed: [String: Data] = [:]
        for (path, data) in entries {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            _ = url.startAccessingSecurityScopedResource()
            lock.lock(); accessing[path] = url; lock.unlock()
            if stale,
               let nd = try? url.bookmarkData(options: .withSecurityScope,
                                              includingResourceValuesForKeys: nil,
                                              relativeTo: nil) {
                refreshed[path] = nd
            }
        }
        if !refreshed.isEmpty {
            lock.lock()
            for (p, d) in refreshed { bookmarks[p] = d }
            saveToDefaults()
            lock.unlock()
        }
    }

    /// コレクション追加時に呼ぶ。ファイルの親フォルダ単位で bookmark を保存する。
    /// 呼び出し時点でファイルがアクセス可能（コピー元 scope 内）である必要がある。
    func registerFolders(for files: [PhotoFile]) {
        let folders = Set(files.map { $0.rawURL.deletingLastPathComponent() })
        var changed = false
        for folder in folders {
            let path = folder.path
            lock.lock(); let exists = bookmarks[path] != nil; lock.unlock()
            if exists { continue }
            guard let data = try? folder.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else { continue }
            lock.lock(); bookmarks[path] = data; lock.unlock()
            // 保存と同時にアクセスを開始しておく（同一セッションで即利用できるように）
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                lock.lock(); accessing[path] = url; lock.unlock()
            }
            changed = true
        }
        if changed { lock.lock(); saveToDefaults(); lock.unlock() }
    }
}

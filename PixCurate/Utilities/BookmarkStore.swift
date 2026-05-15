import Foundation

/// Security-scoped bookmarksでURLを永続化するユーティリティ
enum BookmarkStore {
    nonisolated static func save(url: URL?, key: String) {
        guard
            let url,
            let data = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    nonisolated static func restore(_ key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale, let url { save(url: url, key: key) }
        _ = url?.startAccessingSecurityScopedResource()
        return url
    }
}

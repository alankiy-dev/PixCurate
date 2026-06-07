import Foundation

// MARK: - SourceSpec（スキャン・コピー実行時に渡す情報）

struct SourceSpec: Sendable, Equatable, Hashable {
    let url: URL
    let isRecursive: Bool
}

// MARK: - SourceFolder（永続化モデル）

struct SourceFolder: Identifiable, Sendable {
    let id: UUID
    var bookmarkData: Data
    var isRecursive: Bool
    var displayPath: String   // オフライン時の表示用パス
    var isEnabled: Bool = true // 検索対象＋タブ表示の対象にするか

    /// ブックマーク解決後に設定される（非永続）
    var resolvedURL: URL?
    var isOnline: Bool { resolvedURL != nil }
}

// MARK: - SourceFolder + Codable

extension SourceFolder: Codable {
    enum CodingKeys: String, CodingKey {
        case id, bookmarkData, isRecursive, displayPath, isEnabled
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,   forKey: .id)
        bookmarkData  = try c.decode(Data.self,   forKey: .bookmarkData)
        isRecursive   = try c.decode(Bool.self,   forKey: .isRecursive)
        displayPath   = try c.decode(String.self, forKey: .displayPath)
        isEnabled     = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        resolvedURL   = nil
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,           forKey: .id)
        try c.encode(bookmarkData, forKey: .bookmarkData)
        try c.encode(isRecursive,  forKey: .isRecursive)
        try c.encode(displayPath,  forKey: .displayPath)
        try c.encode(isEnabled,    forKey: .isEnabled)
    }
}

// MARK: - SourceFolderStore

@MainActor
@Observable
final class SourceFolderStore {
    static let shared = SourceFolderStore()

    private(set) var folders: [SourceFolder] = []

    private let udKey = "pixcurate.sourceFolders"

    private init() {
        loadFromDefaults()
    }

    // MARK: - Computed

    /// 有効かつ Security scope が解決済みでオンライン状態のフォルダだけを返す（検索対象）
    var onlineSpecs: [SourceSpec] {
        folders.compactMap { f in
            guard f.isEnabled, let url = f.resolvedURL else { return nil }
            return SourceSpec(url: url, isRecursive: f.isRecursive)
        }
    }

    /// タブ表示の対象となる有効なフォルダ
    var enabledFolders: [SourceFolder] {
        folders.filter { $0.isEnabled }
    }

    // MARK: - 追加

    enum AddError: LocalizedError {
        case duplicate
        case overlap(String)

        var errorDescription: String? {
            switch self {
            case .duplicate:
                return "そのフォルダはすでに登録されています。"
            case .overlap(let path):
                return "「\(path)」の設定と重複しています（サブフォルダを含む指定の範囲内のフォルダ、または逆包含）。"
            }
        }
    }

    func add(url: URL, isRecursive: Bool) throws {
        let newPath = url.resolvingSymlinksInPath().path
        for folder in folders {
            let existPath = (folder.resolvedURL ?? URL(fileURLWithPath: folder.displayPath))
                .resolvingSymlinksInPath().path

            // 同一パス
            if newPath == existPath {
                throw AddError.duplicate
            }

            // 既存がrecursiveで新しいパスを包含
            if folder.isRecursive {
                let base = existPath.hasSuffix("/") ? existPath : existPath + "/"
                if newPath.hasPrefix(base) {
                    throw AddError.overlap(folder.displayPath)
                }
            }

            // 新規がrecursiveで既存パスを包含
            if isRecursive {
                let base = newPath.hasSuffix("/") ? newPath : newPath + "/"
                if existPath.hasPrefix(base) {
                    throw AddError.overlap(folder.displayPath)
                }
            }
        }

        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            throw AddError.duplicate   // フォールバック（通常到達しない）
        }

        _ = url.startAccessingSecurityScopedResource()

        let sf = SourceFolder(
            id: UUID(),
            bookmarkData: bookmarkData,
            isRecursive: isRecursive,
            displayPath: url.path,
            resolvedURL: url
        )
        folders.append(sf)
        saveToDefaults()
    }

    func remove(id: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].resolvedURL?.stopAccessingSecurityScopedResource()
        folders.remove(at: idx)
        saveToDefaults()
    }

    func setRecursive(id: UUID, isRecursive: Bool) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].isRecursive = isRecursive
        saveToDefaults()
    }

    func setEnabled(id: UUID, isEnabled: Bool) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].isEnabled = isEnabled
        saveToDefaults()
    }

    // MARK: - バックグラウンドでブックマーク解決

    func resolveBookmarksInBackground() {
        let entries = folders.map { ($0.id, $0.bookmarkData) }
        Task.detached {
            var resolved: [(UUID, URL?, Data?)] = []
            for (fid, data) in entries {
                var stale = false
                let url = try? URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                if let url { _ = url.startAccessingSecurityScopedResource() }
                // stale なら新しいブックマークデータを生成
                let newData: Data? = (stale == true && url != nil)
                    ? (try? url!.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
                    : nil
                resolved.append((fid, url, newData))
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (fid, url, newData) in resolved {
                    guard let idx = folders.firstIndex(where: { $0.id == fid }) else { continue }
                    folders[idx].resolvedURL = url
                    if let nd = newData { folders[idx].bookmarkData = nd }
                }
                saveToDefaults()
            }
        }
    }

    // MARK: - 永続化

    private func saveToDefaults() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }

    private func loadFromDefaults() {
        guard
            let data = UserDefaults.standard.data(forKey: udKey),
            let decoded = try? JSONDecoder().decode([SourceFolder].self, from: data)
        else { return }
        folders = decoded
        resolveBookmarksInBackground()
    }
}

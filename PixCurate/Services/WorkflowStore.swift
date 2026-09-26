import AppKit
import Observation

/// 「編集アプリ」「プリントアプリ」を登録し、サムネイルからワンタッチで起動するためのストア。
/// 選んだアプリは security-scoped bookmark で永続化し、起動時に解決する。
@Observable
final class WorkflowStore {
    static let shared = WorkflowStore()

    private let editKey  = "pixcurate.workflow.editAppBookmark"
    private let printKey = "pixcurate.workflow.printAppBookmark"

    private(set) var editAppURL: URL?
    private(set) var printAppURL: URL?

    private init() {
        editAppURL  = resolve(editKey)
        printAppURL = resolve(printKey)
    }

    // MARK: - 登録・解除

    func setEditApp(_ url: URL)  { save(url, key: editKey);  editAppURL = url }
    func setPrintApp(_ url: URL) { save(url, key: printKey); printAppURL = url }
    func clearEditApp()  { UserDefaults.standard.removeObject(forKey: editKey);  editAppURL = nil }
    func clearPrintApp() { UserDefaults.standard.removeObject(forKey: printKey); printAppURL = nil }

    /// アプリの表示名（.app サフィックスは除去）
    func displayName(_ url: URL?) -> String? {
        guard let url else { return nil }
        let n = FileManager.default.displayName(atPath: url.path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }

    // MARK: - 起動

    /// 指定ファイル群を登録アプリで開く
    func open(_ files: [URL], with appURL: URL?) {
        guard let appURL, !files.isEmpty else { return }
        let accessed = appURL.startAccessingSecurityScopedResource()
        defer { if accessed { appURL.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.open(files, withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// 編集用に開く（RAW本体を渡す）
    func openForEdit(_ rawURLs: [URL]) { open(rawURLs, with: editAppURL) }

    /// プリント用に開く（現像後の同名JPEGがあればそれ、無ければ本体）
    func openForPrint(_ rawURLs: [URL]) {
        open(rawURLs.map { printSource(for: $0) }, with: printAppURL)
    }

    /// プリント対象の実ファイル：RAWの隣に同名JPEGがあればそれを使う
    func printSource(for rawURL: URL) -> URL {
        let raws: Set<String> = ["raf", "arw", "cr3", "cr2"]
        guard raws.contains(rawURL.pathExtension.lowercased()) else { return rawURL }
        let base = rawURL.deletingPathExtension()
        for ext in ["jpg", "JPG", "jpeg", "JPEG"] {
            let c = base.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: c.path) { return c }
        }
        return rawURL
    }

    // MARK: - 永続化

    private func save(_ url: URL, key: String) {
        if let data = try? url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func resolve(_ key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        let url = try? URL(resolvingBookmarkData: data,
                           options: [.withSecurityScope],
                           relativeTo: nil,
                           bookmarkDataIsStale: &stale)
        if stale, let url {         // 期限切れなら作り直して保存
            save(url, key: key)
        }
        return url
    }
}

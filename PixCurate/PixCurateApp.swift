import SwiftUI

extension Notification.Name {
    static let rescanRequested  = Notification.Name("pixcurate.rescan")
    static let rebuildRequested = Notification.Name("pixcurate.rebuild")
}

@main
struct PixCurateApp: App {
    @State private var showAbout = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(TagStore.shared)
                .environment(LocationStore.shared)
                .environment(DisplaySettings.shared)
                .environment(FilterPresetStore.shared)
                .sheet(isPresented: $showAbout) { AboutView() }
        }
        .commands {
            // アプリメニュー
            CommandGroup(replacing: .appInfo) {
                Button("PixCurate について") { showAbout = true }
            }

            // ファイルメニューを非表示（不要）
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .printItem) { }

            // 編集メニューを非表示（不要）
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .pasteboard) { }
            CommandGroup(replacing: .textEditing) { }

            // ヘルプメニューを非表示（不要）
            CommandGroup(replacing: .help) { }

            // ツールメニュー
            CommandMenu("ツール") {
                Button("再スキャン") {
                    NotificationCenter.default.post(name: .rescanRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("DB再構築…") {
                    NotificationCenter.default.post(name: .rebuildRequested, object: nil)
                }
            }

            // ウインドウメニューを日本語化
            CommandGroup(replacing: .windowArrangement) {
                Button("最小化") {
                    NSApplication.shared.keyWindow?.miniaturize(nil)
                }
                .keyboardShortcut("m", modifiers: .command)

                Button("ズーム") {
                    NSApplication.shared.keyWindow?.zoom(nil)
                }
            }
        }

        WindowGroup(id: "photo-viewer", for: URL.self) { $url in
            PhotoViewerView(url: url ?? URL(fileURLWithPath: "/"))
        }
    }
}

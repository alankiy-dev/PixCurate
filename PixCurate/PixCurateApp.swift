import SwiftUI

extension Notification.Name {
    static let rescanRequested    = Notification.Name("pixcurate.rescan")
    static let rebuildRequested   = Notification.Name("pixcurate.rebuild")
    static let resetWindowState   = Notification.Name("pixcurate.resetWindowState")
    static let showHelp           = Notification.Name("pixcurate.showHelp")
}

// MARK: - App Commands

struct PixCurateCommands: Commands {
    @Binding var showAbout: Bool

    var body: some Commands {
        // PixCurateメニュー
        CommandGroup(replacing: .appInfo) {
            Button("PixCurate について") { showAbout = true }
        }
        CommandGroup(replacing: .appVisibility) {
            Button("PixCurate を非表示") { NSApp.hide(nil) }
                .keyboardShortcut("h", modifiers: .command)
            Button("ほかを非表示") { NSApp.hideOtherApplications(nil) }
                .keyboardShortcut("h", modifiers: [.option, .command])
            Button("すべてを表示") { NSApp.unhideAllApplications(nil) }
        }
        CommandGroup(replacing: .appTermination) {
            Button("PixCurate を終了") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }

        // ファイル・編集メニューを非表示
        CommandGroup(replacing: .newItem) { }
        CommandGroup(replacing: .saveItem) { }
        CommandGroup(replacing: .printItem) { }
        CommandGroup(replacing: .undoRedo) { }
        CommandGroup(replacing: .pasteboard) { }
        CommandGroup(replacing: .textEditing) { }
        CommandGroup(replacing: .help) {
            Button("PixCurate ヘルプ") {
                NotificationCenter.default.post(name: .showHelp, object: nil)
            }
            .keyboardShortcut("/", modifiers: .command)
        }
    }
}

struct PixCurateCommands2: Commands {
    var body: some Commands {
        // Viewメニューを非表示
        CommandGroup(replacing: .toolbar) { }
        CommandGroup(replacing: .sidebar) { }


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

        // ウィンドウメニューに追加
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("画面状態の初期化") {
                NotificationCenter.default.post(name: .resetWindowState, object: nil)
            }
        }
    }
}

// MARK: - App

@main
struct PixCurateApp: App {
    @State private var showAbout = false
    @State private var showHelp  = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(TagStore.shared)
                .environment(LocationStore.shared)
                .environment(DisplaySettings.shared)
                .environment(FilterPresetStore.shared)
                .environment(CollectionStore.shared)
                .sheet(isPresented: $showAbout) { AboutView() }
                .sheet(isPresented: $showHelp) {
                    HelpView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("閉じる") { showHelp = false }
                            }
                        }
                }
                .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
                    showHelp = true
                }
        }
        .commands {
            PixCurateCommands(showAbout: $showAbout)
            PixCurateCommands2()
        }

        WindowGroup(id: "photo-viewer", for: URL.self) { $url in
            PhotoViewerView(url: url ?? URL(fileURLWithPath: "/"))
        }
    }
}

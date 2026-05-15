import SwiftUI

extension Notification.Name {
    static let rescanRequested  = Notification.Name("pixcurate.rescan")
    static let rebuildRequested = Notification.Name("pixcurate.rebuild")
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
        CommandGroup(replacing: .help) { }
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
    }
}

// MARK: - App

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
            PixCurateCommands(showAbout: $showAbout)
            PixCurateCommands2()
        }

        WindowGroup(id: "photo-viewer", for: URL.self) { $url in
            PhotoViewerView(url: url ?? URL(fileURLWithPath: "/"))
        }
    }
}

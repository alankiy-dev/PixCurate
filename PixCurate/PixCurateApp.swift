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
            CommandGroup(replacing: .appInfo) {
                Button("PixCurate について") { showAbout = true }
            }
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

        WindowGroup(id: "photo-viewer", for: URL.self) { $url in
            PhotoViewerView(url: url ?? URL(fileURLWithPath: "/"))
        }
    }
}

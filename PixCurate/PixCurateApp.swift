import SwiftUI

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
        }

        WindowGroup(id: "photo-viewer", for: URL.self) { $url in
            PhotoViewerView(url: url ?? URL(fileURLWithPath: "/"))
        }
    }
}

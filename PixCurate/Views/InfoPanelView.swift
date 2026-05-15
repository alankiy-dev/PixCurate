import SwiftUI

struct InfoPanelView: View {
    enum Tab: String, CaseIterable {
        case rating   = "評価"
        case tags     = "タグ"
        case location = "撮影地"
    }

    let selectedFiles: [PhotoFile]
    let vm: FileListViewModel
    @Environment(TagStore.self) var tagStore
    @Environment(LocationStore.self) var locationStore
    @State private var activeTab: Tab = .rating

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $activeTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)
            .background(.bar)

            Divider()

            switch activeTab {
            case .rating:
                RatingPanelView(selectedFiles: selectedFiles, vm: vm)
            case .tags:
                TagPanelView(selectedFiles: selectedFiles, vm: vm)
                    .environment(tagStore)
            case .location:
                LocationPanelView(selectedFiles: selectedFiles, vm: vm)
                    .environment(locationStore)
            }
        }
        .frame(width: 240)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

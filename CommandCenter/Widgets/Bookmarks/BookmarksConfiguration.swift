import SwiftUI

struct BookmarksConfiguration: WidgetConfiguration {
    var folder = ""          // "" = all
    var tileSize: Double = 64

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Picker("Folder", selection: config.folder) {
                Text("All").tag("")
                ForEach(Array(Set(BookmarksStore.all().map(\.folder))).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
            }
            Slider(value: config.tileSize, in: 48...96) { Text("Tile size") }
        }
    }
}

import SwiftUI

struct DiskStorageConfiguration: WidgetConfiguration {
    var root = "~"

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            HStack {
                TextField("Folder to analyze", text: config.root)
                Button("Choose…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                    if p.runModal() == .OK, let u = p.url { config.wrappedValue.root = (u.path as NSString).abbreviatingWithTildeInPath }
                }
            }
        }
    }
}

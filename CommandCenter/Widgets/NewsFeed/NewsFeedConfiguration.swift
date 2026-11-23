import SwiftUI

struct NewsFeedConfiguration: WidgetConfiguration {
    var feeds: [String] = ["https://hnrss.org/frontpage", "https://www.theverge.com/rss/index.xml"]
    var unreadOnly = false

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Section("Feeds (RSS or Atom URLs)") {
                ForEach(config.feeds.indices, id: \.self) { i in
                    HStack {
                        TextField("URL", text: config.feeds[i])
                        Button { config.wrappedValue.feeds.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button("Add Feed") { config.wrappedValue.feeds.append("https://") }
            }
            Toggle("Unread only", isOn: config.unreadOnly)
        }
    }
}

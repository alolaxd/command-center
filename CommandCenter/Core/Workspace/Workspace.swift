import Foundation

struct WidgetInstance: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: String
    var frame: GridRect
    var config: Data
    var isHidden: Bool = false
}

struct Workspace: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var columns: Int = 12
    var widgets: [WidgetInstance] = []
}

/// Portable layout export format.
struct LayoutExport: Codable {
    var version = 1
    var exportedAt = Date()
    var workspaces: [Workspace]
}

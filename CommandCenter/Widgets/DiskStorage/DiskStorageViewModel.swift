import Foundation

@MainActor @Observable
final class DiskStorageViewModel {
    /// Scans are expensive, so results are cached per folder for the app session.
    private static var cache: [String: DiskStorageStore.ScanResult] = [:]

    var result: DiskStorageStore.ScanResult?
    var volumes: [VolumeInfo] = []
    var trash: Int64?
    var scanning = false
    var progress = ""
    var drillPath: String?

    func load(_ config: DiskStorageConfiguration) async {
        volumes = DiskStorageStore.volumes()
        trash = await DiskStorageStore.trashSize()
        let root = drillPath ?? (config.root as NSString).expandingTildeInPath
        if let cached = Self.cache[root] { result = cached } else { await scan(root) }
    }

    func scan(_ root: String) async {
        scanning = true
        result = nil
        let r = await DiskStorageStore.scan(URL(fileURLWithPath: root)) { name in
            Task { @MainActor in self.progress = name }
        }
        Self.cache[root] = r
        result = r
        scanning = false
    }

    func drill(_ item: DiskItem, config: DiskStorageConfiguration) async {
        guard item.isDirectory else { return }
        drillPath = item.path
        await load(config)
    }

    func up(_ config: DiskStorageConfiguration) async {
        let root = (config.root as NSString).expandingTildeInPath
        guard let p = drillPath else { return }
        let parent = (p as NSString).deletingLastPathComponent
        drillPath = parent.count <= root.count ? nil : parent
        await load(config)
    }
}

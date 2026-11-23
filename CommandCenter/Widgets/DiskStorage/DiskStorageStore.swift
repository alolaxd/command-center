import AppKit
import Foundation

struct DiskItem: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let size: Int64
    let isDirectory: Bool
    var name: String { (path as NSString).lastPathComponent }
}

struct VolumeInfo: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let total: Int64
    let available: Int64
    let isRemovable: Bool
    let isInternal: Bool
}

enum DiskStorageStore {
    struct ScanResult: Sendable {
        var children: [DiskItem] = []
        var largestFiles: [DiskItem] = []
        var scannedAt = Date()
    }

    /// Sizes of each immediate child of `root`, plus the largest individual files found.
    static func scan(_ root: URL, progress: @escaping @Sendable (String) -> Void) async -> ScanResult {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
            var result = ScanResult()
            var largest: [DiskItem] = []
            let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [])) ?? []
            for child in children {
                if Task.isCancelled { break }
                let rv = try? child.resourceValues(forKeys: Set(keys))
                if rv?.isSymbolicLink == true { continue }
                var total: Int64 = 0
                if rv?.isDirectory == true {
                    progress(child.lastPathComponent)
                    if let e = fm.enumerator(at: child, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) {
                        for case let url as URL in e {
                            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isDirectory != true else { continue }
                            let s = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                            total += s
                            if s > (largest.count < 20 ? 0 : largest.last!.size) {
                                largest.append(DiskItem(path: url.path, size: s, isDirectory: false))
                                largest.sort { $0.size > $1.size }
                                if largest.count > 20 { largest.removeLast() }
                            }
                        }
                    }
                } else {
                    total = Int64(rv?.totalFileAllocatedSize ?? rv?.fileAllocatedSize ?? 0)
                }
                result.children.append(DiskItem(path: child.path, size: total, isDirectory: rv?.isDirectory == true))
            }
            result.children.sort { $0.size > $1.size }
            result.largestFiles = largest
            return result
        }.value
    }

    static func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsBrowsableKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []).compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsBrowsable != false else { return nil }
            return VolumeInfo(url: url, name: v.volumeName ?? url.lastPathComponent, total: Int64(v.volumeTotalCapacity ?? 0),
                              available: v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0),
                              isRemovable: v.volumeIsRemovable ?? false, isInternal: v.volumeIsInternal ?? true)
        }
    }

    /// Size of ~/.Trash (nil when macOS denies access — grant Full Disk Access to see it).
    static func trashSize() async -> Int64? {
        await Task.detached(priority: .utility) {
            let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            guard (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) != nil,
                  let e = FileManager.default.enumerator(at: trash, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return nil }
            var total: Int64 = 0
            for case let u as URL in e { total += Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0) }
            return total
        }.value
    }

    static func emptyTrash() async -> String? {
        let (_, err) = await AppleScriptRunner.run("tell application \"Finder\" to empty trash")
        return err
    }

    @MainActor static func eject(_ v: VolumeInfo) -> String? {
        do { try NSWorkspace.shared.unmountAndEjectDevice(at: v.url); return nil } catch { return error.localizedDescription }
    }

    /// Squarified treemap layout.
    static func treemap(_ items: [DiskItem], in rect: CGRect) -> [(DiskItem, CGRect)] {
        let total = items.map { Double($0.size) }.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return [] }
        let scale = Double(rect.width * rect.height) / total
        var remaining = items.filter { $0.size > 0 }.map { ($0, Double($0.size) * scale) }
        var out: [(DiskItem, CGRect)] = []
        var r = rect
        func worst(_ row: [Double], _ side: Double) -> Double {
            let s = row.reduce(0, +)
            guard let mx = row.max(), let mn = row.min(), s > 0, mn > 0 else { return .infinity }
            return max(side * side * mx / (s * s), (s * s) / (side * side * mn))
        }
        while !remaining.isEmpty {
            let side = Double(min(r.width, r.height))
            var row: [(DiskItem, Double)] = [remaining.removeFirst()]
            while let next = remaining.first, worst(row.map(\.1) + [next.1], side) <= worst(row.map(\.1), side) {
                row.append(remaining.removeFirst())
            }
            let rowArea = row.map(\.1).reduce(0, +)
            if r.width >= r.height {
                let w = CGFloat(rowArea / Double(r.height))
                var y = r.minY
                for (item, a) in row { let h = CGFloat(a) / w; out.append((item, CGRect(x: r.minX, y: y, width: w, height: h))); y += h }
                r = CGRect(x: r.minX + w, y: r.minY, width: r.width - w, height: r.height)
            } else {
                let h = CGFloat(rowArea / Double(r.width))
                var x = r.minX
                for (item, a) in row { let w = CGFloat(a) / h; out.append((item, CGRect(x: x, y: r.minY, width: w, height: h))); x += w }
                r = CGRect(x: r.minX, y: r.minY + h, width: r.width, height: r.height - h)
            }
        }
        return out
    }
}

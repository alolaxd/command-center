import Foundation

@MainActor @Observable
final class NetworkMonitorViewModel {
    var addresses: [NetworkMonitorStore.Interface] = []
    var publicIP: String?
    var down: [Double] = []
    var up: [Double] = []
    var connections: [NetConnection] = []
    var hostNames: [String: String] = [:]
    var pings: [String: [Double]] = [:]
    var tab = 0
    private var prev: (UInt64, UInt64, Date)?
    private var tick = 0

    func refresh(_ config: NetworkMonitorConfiguration) async {
        tick += 1
        let (i, o) = SystemSampler.networkBytes()
        let now = Date()
        if let p = prev {
            let dt = max(0.1, now.timeIntervalSince(p.2))
            push(&down, Double(i &- p.0) / dt)
            push(&up, Double(o &- p.1) / dt)
        }
        prev = (i, o, now)
        if tick % 5 == 1 {
            addresses = NetworkMonitorStore.localAddresses()
            if UserDefaults.standard.bool(forKey: SettingsKey.publicIPLookup), publicIP == nil || tick % 150 == 1 {
                publicIP = await NetworkMonitorStore.publicIP()
            }
            for h in config.pingHosts {
                var arr = pings[h] ?? []
                arr.append(await NetworkMonitorStore.ping(h) ?? -1)
                if arr.count > 30 { arr.removeFirst() }
                pings[h] = arr
            }
            if config.showConnections && tab == 1 { await loadConnections(config) }
        }
    }

    func loadConnections(_ config: NetworkMonitorConfiguration) async {
        connections = await NetworkMonitorStore.connections()
        guard config.resolveHosts else { return }
        for c in connections where hostNames[c.remoteHost] == nil {
            hostNames[c.remoteHost] = await NetworkMonitorStore.reverseDNS(c.remoteHost) ?? c.remoteHost
        }
    }

    private func push(_ a: inout [Double], _ v: Double) {
        a.append(v)
        if a.count > 60 { a.removeFirst() }
    }
}

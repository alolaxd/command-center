import Darwin
import Foundation
import Network

struct NetConnection: Identifiable, Hashable, Sendable {
    var id: String { "\(pid)-\(local)-\(remote)" }
    let process: String
    let pid: Int
    let local: String
    let remote: String
    let remoteHost: String
    let remotePort: String
    let state: String
}

enum NetworkMonitorStore {
    struct Interface: Hashable, Sendable { let name: String; let address: String; let isIPv6: Bool }

    static func localAddresses() -> [Interface] {
        var out: [Interface] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let family = sa.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let addr = String(cString: host)
            if addr.hasPrefix("fe80") { continue }
            out.append(Interface(name: String(cString: ifa.ifa_name), address: addr, isIPv6: family == UInt8(AF_INET6)))
        }
        return out.sorted { ($0.isIPv6 ? 1 : 0, $0.name) < ($1.isIPv6 ? 1 : 0, $1.name) }
    }

    static func publicIP() async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://api.ipify.org")!) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Established TCP connections for processes the user can see (via lsof).
    static func connections() async -> [NetConnection] {
        let r = await Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-F", "pcnT"], timeout: 10)
        var out: [NetConnection] = []
        var pid = 0, cmd = ""
        var name = ""
        for line in r.stdout.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int(value) ?? 0
            case "c": cmd = value
            case "n": name = value
            case "T":
                guard value.hasPrefix("ST="), name.contains("->") else { continue }
                let parts = name.components(separatedBy: "->")
                let remote = parts[1]
                let colon = remote.lastIndex(of: ":") ?? remote.endIndex
                let host = String(remote[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                let port = colon < remote.endIndex ? String(remote[remote.index(after: colon)...]) : ""
                out.append(NetConnection(process: cmd, pid: pid, local: parts[0], remote: remote, remoteHost: host, remotePort: port,
                                         state: String(value.dropFirst(3))))
                name = ""
            default: break
            }
        }
        return Array(Set(out)).sorted { ($0.process, $0.remote) < ($1.process, $1.remote) }
    }

    /// ICMP ping via /sbin/ping; returns latency in ms.
    static func ping(_ host: String) async -> Double? {
        let r = await Shell.run("/sbin/ping", ["-c", "1", "-t", "2", host], timeout: 4)
        guard let range = r.stdout.range(of: #"time=([0-9.]+)"#, options: .regularExpression) else { return nil }
        return Double(r.stdout[range].dropFirst(5))
    }

    static func reverseDNS(_ ip: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo(ai_flags: AI_NUMERICHOST, ai_family: AF_UNSPEC, ai_socktype: 0, ai_protocol: 0,
                                     ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
                var res: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(ip, nil, &hints, &res) == 0, let ai = res else { cont.resume(returning: nil); return }
                defer { freeaddrinfo(res) }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let ok = getnameinfo(ai.pointee.ai_addr, ai.pointee.ai_addrlen, &host, socklen_t(host.count), nil, 0, NI_NAMEREQD) == 0
                cont.resume(returning: ok ? String(cString: host) : nil)
            }
        }
    }
}

/// Current path (Wi-Fi / Ethernet / …) via Network.framework.
@MainActor @Observable
final class NetworkPathObserver {
    static let shared = NetworkPathObserver()
    var interfaceType = "Unknown"
    var isConnected = true
    var isExpensive = false
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let type: String = path.usesInterfaceType(.wifi) ? "Wi-Fi" : path.usesInterfaceType(.wiredEthernet) ? "Ethernet"
                : path.usesInterfaceType(.cellular) ? "Cellular" : path.usesInterfaceType(.other) ? "Other" : "None"
            Task { @MainActor in
                let o = NetworkPathObserver.shared
                o.interfaceType = type
                o.isConnected = path.status == .satisfied
                o.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "cc.netpath"))
    }
}

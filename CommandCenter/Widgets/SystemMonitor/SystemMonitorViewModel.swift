import Foundation

@MainActor @Observable
final class SystemMonitorViewModel {
    var snap = SystemSampler.Snapshot()
    var cpuHistory: [Double] = []
    var memHistory: [Double] = []
    var gpuHistory: [Double] = []
    var netInHistory: [Double] = []
    var netOutHistory: [Double] = []
    var diskHistory: [Double] = []
    private let historySeconds = 60.0

    func refresh(_ config: SystemMonitorConfiguration) async {
        let s = await SystemSampler.shared.sample(includeProcesses: config.showProcesses)
        snap = s
        let cap = Int(historySeconds / config.interval)
        push(&cpuHistory, s.cpuTotal, cap)
        push(&memHistory, s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0, cap)
        push(&gpuHistory, s.gpu ?? 0, cap)
        push(&netInHistory, s.netInPerSec, cap)
        push(&netOutHistory, s.netOutPerSec, cap)
        push(&diskHistory, s.diskReadPerSec + s.diskWritePerSec, cap)
    }

    private func push(_ a: inout [Double], _ v: Double, _ cap: Int) {
        a.append(v)
        if a.count > cap { a.removeFirst(a.count - cap) }
    }

    func top(_ config: SystemMonitorConfiguration) -> [SystemSampler.ProcessSample] {
        let sorted = config.sortBy == .cpu ? snap.processes.sorted { $0.cpu > $1.cpu } : snap.processes.sorted { $0.memory > $1.memory }
        return Array(sorted.prefix(5))
    }
}

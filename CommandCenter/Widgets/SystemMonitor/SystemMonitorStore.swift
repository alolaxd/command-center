import Darwin
import Foundation
import IOKit

/// Low-level system sampling via Mach, sysctl, libproc and IOKit — no shelling out.
actor SystemSampler {
    static let shared = SystemSampler()

    struct Snapshot: Sendable {
        var cores: [Double] = []          // 0...1 per core
        var cpuTotal: Double = 0
        var memUsed: UInt64 = 0
        var memTotal: UInt64 = 0
        var memCompressed: UInt64 = 0
        var memWired: UInt64 = 0
        var memApp: UInt64 = 0
        var pressure: Int = 1              // 1 normal, 2 warn, 4 critical
        var gpu: Double?                   // 0...1
        var diskReadPerSec: Double = 0
        var diskWritePerSec: Double = 0
        var netInPerSec: Double = 0
        var netOutPerSec: Double = 0
        var processes: [ProcessSample] = []
    }

    struct ProcessSample: Sendable, Identifiable, Hashable {
        var id: pid_t { pid }
        let pid: pid_t
        let name: String
        let cpu: Double     // percent of one core
        let memory: UInt64
    }

    private var prevTicks: [[UInt32]] = []
    private var prevDisk: (r: UInt64, w: UInt64, t: Date)?
    private var prevNet: (i: UInt64, o: UInt64, t: Date)?
    private var prevProc: [pid_t: UInt64] = [:]
    private var prevProcTime: UInt64 = 0
    private let timebase: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()

    func sample(includeProcesses: Bool = true) -> Snapshot {
        var s = Snapshot()
        (s.cores, s.cpuTotal) = cpu()
        memory(&s)
        s.gpu = Self.gpuUtilization()
        disk(&s)
        let (i, o) = Self.networkBytes()
        let now = Date()
        if let p = prevNet {
            let dt = max(0.1, now.timeIntervalSince(p.t))
            s.netInPerSec = Double(i &- p.i) / dt
            s.netOutPerSec = Double(o &- p.o) / dt
        }
        prevNet = (i, o, now)
        if includeProcesses { s.processes = processes() }
        return s
    }

    // MARK: CPU
    private func cpu() -> ([Double], Double) {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return ([], 0) }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        var ticks: [[UInt32]] = []
        for c in 0..<Int(count) {
            let base = c * Int(CPU_STATE_MAX)
            ticks.append((0..<Int(CPU_STATE_MAX)).map { UInt32(bitPattern: info[base + $0]) })
        }
        defer { prevTicks = ticks }
        guard prevTicks.count == ticks.count else { return (Array(repeating: 0, count: ticks.count), 0) }
        var loads: [Double] = []
        var busyAll = 0.0, totalAll = 0.0
        for (now, prev) in zip(ticks, prevTicks) {
            let d = zip(now, prev).map { Double($0 &- $1) }
            let busy = d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_SYSTEM)] + d[Int(CPU_STATE_NICE)]
            let total = busy + d[Int(CPU_STATE_IDLE)]
            loads.append(total > 0 ? busy / total : 0)
            busyAll += busy; totalAll += total
        }
        return (loads, totalAll > 0 ? busyAll / totalAll : 0)
    }

    // MARK: Memory
    private func memory(_ s: inout Snapshot) {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        s.memTotal = size
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            s.memApp = UInt64(stats.internal_page_count &- stats.purgeable_count) * page
            s.memWired = UInt64(stats.wire_count) * page
            s.memCompressed = UInt64(stats.compressor_page_count) * page
            s.memUsed = s.memApp + s.memWired + s.memCompressed
        }
        var level: Int32 = 1
        var l2 = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &l2, nil, 0)
        s.pressure = Int(level)
    }

    // MARK: GPU (IOAccelerator performance statistics)
    static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let util = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber {
                best = max(best ?? 0, util.doubleValue / 100)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return best
    }

    // MARK: Disk (IOBlockStorageDriver statistics)
    private func disk(_ s: inout Snapshot) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var r: UInt64 = 0, w: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                r += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                w += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        let now = Date()
        if let p = prevDisk {
            let dt = max(0.1, now.timeIntervalSince(p.t))
            s.diskReadPerSec = Double(r &- p.r) / dt
            s.diskWritePerSec = Double(w &- p.w) / dt
        }
        prevDisk = (r, w, now)
    }

    // MARK: Network (64-bit counters via NET_RT_IFLIST2)
    static func networkBytes(interface: String? = nil) -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return (0, 0) }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return (0, 0) }
        var inBytes: UInt64 = 0, outBytes: UInt64 = 0
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.load(fromByteOffset: offset, as: if_msghdr.self)
                if Int32(hdr.ifm_type) == RTM_IFINFO2 {
                    let h2 = raw.load(fromByteOffset: offset, as: if_msghdr2.self)
                    let isLoopback = (h2.ifm_flags & IFF_LOOPBACK) != 0
                    var name = ""
                    if let interface {
                        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                        if if_indextoname(UInt32(h2.ifm_index), &buf) != nil { name = String(cString: buf) }
                        if name == interface { inBytes += h2.ifm_data.ifi_ibytes; outBytes += h2.ifm_data.ifi_obytes }
                    } else if !isLoopback {
                        inBytes += h2.ifm_data.ifi_ibytes
                        outBytes += h2.ifm_data.ifi_obytes
                    }
                }
                guard hdr.ifm_msglen > 0 else { break }
                offset += Int(hdr.ifm_msglen)
            }
        }
        return (inBytes, outBytes)
    }

    // MARK: Processes (libproc)
    private func processes() -> [ProcessSample] {
        if AppPaths.demoMode {
            return [("Xcode", 18.4, 2_100), ("Safari", 9.2, 1_250), ("Command Center", 3.1, 180), ("WindowServer", 6.7, 420),
                    ("Music", 1.2, 260), ("Notes", 0.4, 140)].enumerated().map {
                ProcessSample(pid: pid_t(1000 + $0.offset), name: $0.element.0, cpu: $0.element.1, memory: UInt64($0.element.2) << 20)
            }
        }
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let nowTime = mach_absolute_time()
        let wallNs = prevProcTime == 0 ? 0 : Double(nowTime - prevProcTime) * timebase
        var next: [pid_t: UInt64] = [:]
        var out: [ProcessSample] = []
        for pid in pids.prefix(Int(max(0, n))) where pid > 0 {
            var info = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard ok == 0 else { continue }
            let cpuTime = info.ri_user_time + info.ri_system_time
            next[pid] = cpuTime
            var cpu = 0.0
            if wallNs > 0, let prev = prevProc[pid], cpuTime >= prev {
                cpu = Double(cpuTime - prev) * timebase / wallNs * 100
            }
            out.append(ProcessSample(pid: pid, name: Self.processName(pid), cpu: cpu, memory: info.ri_phys_footprint))
        }
        prevProc = next
        prevProcTime = nowTime
        return out
    }

    static func processName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 1024)
        if proc_name(pid, &buf, UInt32(buf.count)) > 0 {
            let name = String(cString: buf)
            // Version-named binaries (e.g. ~/.local/share/claude/versions/2.1.330) → use the tool's folder name.
            if name.first?.isNumber == true, name.allSatisfy({ $0.isNumber || $0 == "." }), let path = processPath(pid) {
                let parts = path.split(separator: "/")
                if let i = parts.lastIndex(of: "versions"), i > 0 { return String(parts[i - 1]) }
            }
            return name
        }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 { return (String(cString: path) as NSString).lastPathComponent }
        return "pid \(pid)"
    }

    static func processPath(_ pid: pid_t) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return proc_pidpath(pid, &path, UInt32(path.count)) > 0 ? String(cString: path) : nil
    }

    /// Sends SIGTERM (or SIGKILL when `force`).
    @discardableResult
    nonisolated static func kill(_ pid: pid_t, force: Bool = false) -> Bool {
        Darwin.kill(pid, force ? SIGKILL : SIGTERM) == 0
    }
}

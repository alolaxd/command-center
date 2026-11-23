import XCTest
@testable import Command_Center

@MainActor
final class SystemInfoTests: XCTestCase {
    // MARK: System Monitor
    func testSystemSamplerProducesSaneValues() async {
        _ = await SystemSampler.shared.sample()
        try? await Task.sleep(for: .milliseconds(600))
        let s = await SystemSampler.shared.sample()
        XCTAssertEqual(s.cores.count, ProcessInfo.processInfo.processorCount, "per-core CPU")
        XCTAssertTrue(s.cores.allSatisfy { (0...1).contains($0) })
        XCTAssertTrue((0...1).contains(s.cpuTotal))
        XCTAssertGreaterThan(s.memTotal, 1 << 30)
        XCTAssertGreaterThan(s.memUsed, 0); XCTAssertLessThan(s.memUsed, s.memTotal)
        XCTAssertTrue([1, 2, 4].contains(s.pressure))
        XCTAssertGreaterThan(s.processes.count, 20, "process list via libproc")
        XCTAssertTrue(s.processes.contains { $0.pid == getpid() })
        XCTAssertGreaterThanOrEqual(s.diskReadPerSec, 0)
        let vm = SystemMonitorViewModel()
        var c = SystemMonitorConfiguration(); c.sortBy = .memory
        await vm.refresh(c); await vm.refresh(c)
        XCTAssertEqual(vm.top(c).count, 5)
        XCTAssertGreaterThanOrEqual(vm.top(c)[0].memory, vm.top(c)[4].memory)
        XCTAssertEqual(vm.cpuHistory.count, 2)
    }

    func testKillTerminatesChildProcess() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep"); p.arguments = ["30"]
        try? p.run()
        XCTAssertTrue(SystemSampler.kill(p.processIdentifier))
        p.waitUntilExit()
        XCTAssertEqual(p.terminationReason, .uncaughtSignal)
    }

    // MARK: Network
    func testNetworkMonitor() async {
        XCTAssertFalse(NetworkMonitorStore.localAddresses().isEmpty, "at least one IP address")
        let (i, o) = SystemSampler.networkBytes()
        XCTAssertGreaterThan(i + o, 0)
        // (ICMP to 127.0.0.1 is filtered on some Macs; use a public anycast host when online.)
        if networkAvailable() {
            let ping = await NetworkMonitorStore.ping("1.1.1.1")
            XCTAssertNotNil(ping); XCTAssertLessThan(ping ?? 9999, 1000)
        }
        let unreachable = await NetworkMonitorStore.ping("192.0.2.1")   // TEST-NET-1, never answers
        XCTAssertNil(unreachable, "timeouts are reported as nil, not hangs")
        let conns = await NetworkMonitorStore.connections()
        XCTAssertTrue(conns.allSatisfy { !$0.process.isEmpty && !$0.remotePort.isEmpty })
        let vm = NetworkMonitorViewModel()
        await vm.refresh(NetworkMonitorConfiguration(pingHosts: ["192.0.2.1"]))
        await vm.refresh(NetworkMonitorConfiguration(pingHosts: ["192.0.2.1"]))
        XCTAssertEqual(vm.down.count, 1)
        XCTAssertEqual(vm.pings["192.0.2.1"]?.last, -1, "timeout recorded for the latency graph")
    }

    // MARK: Disk
    func testDiskScanTreemapAndVolumes() async throws {
        let root = tempDir()
        let big = root.appendingPathComponent("big"); try FileManager.default.createDirectory(at: big, withIntermediateDirectories: true)
        try Data(count: 2_000_000).write(to: big.appendingPathComponent("a.bin"))
        try Data(count: 300_000).write(to: root.appendingPathComponent("small.bin"))
        let r = await DiskStorageStore.scan(root) { _ in }
        XCTAssertEqual(r.children.first?.name, "big", "sorted by size")
        XCTAssertEqual(r.largestFiles.first?.name, "a.bin")
        let rect = CGRect(x: 0, y: 0, width: 300, height: 200)
        let items = [DiskItem(path: "/a", size: 600, isDirectory: true), DiskItem(path: "/b", size: 300, isDirectory: true), DiskItem(path: "/c", size: 100, isDirectory: false)]
        let map = DiskStorageStore.treemap(items, in: rect)
        XCTAssertEqual(map.count, 3)
        let area = map.map { $0.1.width * $0.1.height }
        XCTAssertEqual(area[0] / area.reduce(0, +), 0.6, accuracy: 0.01, "area proportional to size")
        XCTAssertTrue(map.allSatisfy { rect.insetBy(dx: -0.5, dy: -0.5).contains($0.1) })
        for i in 0..<map.count { for j in (i + 1)..<map.count { XCTAssertLessThan(map[i].1.intersection(map[j].1).width * map[i].1.intersection(map[j].1).height, 0.5) } }
        XCTAssertTrue(DiskStorageStore.volumes().contains { $0.isInternal && $0.total > 0 })
    }

    // MARK: Battery
    func testBatteryRead() {
        let b = BatteryStore.read()
        if b.present {
            XCTAssertTrue((0...100).contains(b.percent))
            if let h = b.health { XCTAssertTrue((0.3...1).contains(h)) }
            BatteryStore.record()
            XCTAssertFalse(BatteryStore.samples(since: Date().addingTimeInterval(-60)).isEmpty, "charge history recorded")
        }
    }

    // MARK: Email (Apple Mail)
    func testMailSenderParsing() async throws {
        let m = MailMessage(id: 1, sender: "\"Ada Lovelace\" <ada@example.com>", subject: "Hi", date: Date(), read: false, flagged: false)
        XCTAssertEqual(m.senderName, "Ada Lovelace"); XCTAssertEqual(m.senderEmail, "ada@example.com")
        var c = EmailDigestConfiguration(); c.vips = ["ada@"]; c.vipOnly = true
        let vm = EmailDigestViewModel()
        vm.messages = [m, MailMessage(id: 2, sender: "news@x.com", subject: "Deals", date: Date(), read: true, flagged: false)]
        XCTAssertEqual(vm.visible(c).map(\.id), [1], "VIP filter")
        try XCTSkipUnless(EmailDigestStore.mailRunning, "Mail.app not running")
        let (msgs, err) = await EmailDigestStore.latest(limit: 5)
        if err == nil { XCTAssertLessThanOrEqual(msgs.count, 5) }
    }

    // MARK: Weather
    func testWeatherCodesAndLiveForecast() async throws {
        XCTAssertEqual(WeatherStore.describe(0).1, "sun.max")
        XCTAssertEqual(WeatherStore.describe(95).0, "Thunderstorm")
        XCTAssertTrue(WeatherStore.isSevere(99)); XCTAssertFalse(WeatherStore.isSevere(2))
        try XCTSkipUnless(networkAvailable(), "offline")
        let paris = try await XCTUnwrapAsync(await WeatherStore.geocode("Paris"))
        XCTAssertEqual(paris.lat, 48.85, accuracy: 0.2)
        let r = try await WeatherStore.forecast(paris, fahrenheit: false)
        XCTAssertEqual(r.days.count, 7)
        XCTAssertTrue((-50...60).contains(r.temp))
        let radar = await WeatherStore.radarTileTemplate()
        XCTAssertTrue(radar?.contains("{z}/{x}/{y}") ?? false)
    }

    // MARK: News
    func testFeedParsingAndReader() async throws {
        let rss = """
        <?xml version="1.0"?><rss><channel><title>Feed A</title>
        <item><title>Hello &amp; welcome</title><link>https://a.com/1</link><pubDate>Mon, 23 Nov 2026 10:00:00 +0000</pubDate>
        <description><![CDATA[<p>Body <b>bold</b></p>]]></description></item></channel></rss>
        """
        let (title, entries) = FeedParser(data: Data(rss.utf8)).parse()
        XCTAssertEqual(title, "Feed A"); XCTAssertEqual(entries.first?.title, "Hello & welcome")
        XCTAssertEqual(entries.first?.link, "https://a.com/1"); XCTAssertNotNil(entries.first?.date)
        let atom = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Atom</title><entry><title>Post</title>
        <link rel="alternate" href="https://b.com/p"/><updated>2026-11-23T10:00:00Z</updated><summary>Sum</summary></entry></feed>
        """
        let (_, ae) = FeedParser(data: Data(atom.utf8)).parse()
        XCTAssertEqual(ae.first?.link, "https://b.com/p"); XCTAssertNotNil(ae.first?.date)
        XCTAssertEqual(ReaderExtractor.stripTags("<p>Hi &amp; <i>there</i></p>"), "Hi & there")
        try XCTSkipUnless(networkAvailable(), "offline")
        let items = await NewsStore.fetch("https://hnrss.org/frontpage")
        XCTAssertFalse(items.isEmpty, "live RSS fetch")
        NewsStore.upsert(items)
        NewsStore.setRead(items[0].id)
        XCTAssertTrue(NewsStore.items(feeds: ["https://hnrss.org/frontpage"]).contains { $0.id == items[0].id && $0.read })
        let article = await ReaderExtractor.extract(URL(string: "https://example.com")!)
        XCTAssertNotNil(article)
    }

    // MARK: Bookmarks
    func testBookmarksAddReorderHealth() async throws {
        let server = try LocalHTTPServer()
        BookmarksStore.add(url: server.url("/ok"), title: "Alive", folder: "Test")
        BookmarksStore.add(url: server.url("/gone"), title: "Dead", folder: "Test")
        let vm = BookmarksViewModel()
        vm.load()
        let alive = vm.bookmarks.first { $0.title == "Alive" }!, dead = vm.bookmarks.first { $0.title == "Dead" }!
        vm.move(dead.id, before: alive.id)
        XCTAssertLessThan(vm.bookmarks.firstIndex { $0.id == dead.id }!, vm.bookmarks.firstIndex { $0.id == alive.id }!)
        await vm.checkLinks()
        XCTAssertFalse(vm.bookmarks.first { $0.title == "Alive" }!.isDead)
        XCTAssertTrue(vm.bookmarks.first { $0.title == "Dead" }!.isDead, "404 flagged as dead")
        vm.folder = "Test"; vm.query = "dea"
        XCTAssertEqual(vm.visible.map(\.title), ["Dead"])
        vm.bookmarks.filter { $0.folder == "Test" }.forEach(BookmarksStore.delete)
    }
}

func XCTUnwrapAsync<T>(_ v: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T { try XCTUnwrap(v, file: file, line: line) }

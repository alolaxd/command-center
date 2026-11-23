import AppKit
import Network
import SwiftUI
import XCTest
@testable import Command_Center

/// Pumps the main run loop until `condition` holds or `timeout` elapses.
@MainActor
func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}

/// Tiny local HTTP server: /ok → 200, /fail → 500, anything else → 404.
final class LocalHTTPServer {
    let listener: NWListener
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let req = String(decoding: data ?? Data(), as: UTF8.self)
                let path = req.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let (code, text) = path.hasPrefix("/ok") ? (200, "OK") : path.hasPrefix("/fail") ? (500, "Internal Server Error") : (404, "Not Found")
                let body = "{\"status\":\(code)}"
                let resp = "HTTP/1.1 \(code) \(text)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: .global())
        _ = ready.wait(timeout: .now() + 5)
    }

    func url(_ path: String) -> String { "http://127.0.0.1:\(port)\(path)" }
    deinit { listener.cancel() }
}

/// Async-friendly wait: suspends (instead of blocking) so MainActor tasks keep running.
@MainActor
func waitUntilAsync(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

func networkAvailable() -> Bool {
    Shell.runSync("/sbin/ping", ["-c", "1", "-t", "2", "1.1.1.1"], timeout: 4).ok
}

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("cc-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

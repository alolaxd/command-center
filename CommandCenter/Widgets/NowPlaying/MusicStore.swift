import AppKit
import Foundation
import GRDB

struct NowPlayingInfo: Equatable, Sendable {
    enum Source: String, Sendable { case music = "Music", spotify = "Spotify" }
    var source: Source
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var artworkURL: String?
}

struct PlayHistory: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "music_history"
    var id: String { "\(title)|\(artist)|\(playedAt.timeIntervalSince1970)" }
    var title: String
    var artist: String
    var source: String
    var playedAt: Date
}

/// Apple Music and Spotify via AppleScript. Players are only queried while running (never launched).
@MainActor
enum MusicStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("music.v1") { db in
            try db.create(table: "music_history") { t in
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("source", .text).notNull()
                t.column("playedAt", .datetime).notNull().indexed()
            }
        }
    }

    static func isRunning(_ s: NowPlayingInfo.Source) -> Bool {
        let id = s == .music ? "com.apple.Music" : "com.spotify.client"
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    static func current() async -> NowPlayingInfo? {
        // Prefer whichever player is actually playing.
        var candidates: [NowPlayingInfo] = []
        for s in [NowPlayingInfo.Source.spotify, .music] where isRunning(s) {
            if let info = await query(s) { candidates.append(info) }
        }
        return candidates.first { $0.isPlaying } ?? candidates.first
    }

    private static func query(_ s: NowPlayingInfo.Source) async -> NowPlayingInfo? {
        let app = s.rawValue
        let extra = s == .spotify ? " & tab & (artwork url of current track)" : ""
        let script = """
        tell application "\(app)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & tab & (artist of t) & tab & (album of t) & tab & (duration of t) & tab & (player position) & tab & (player state as string)\(extra)
        end tell
        """
        guard let out = await AppleScriptRunner.run(script).0, !out.isEmpty else { return nil }
        let f = out.components(separatedBy: "\t")
        guard f.count >= 6 else { return nil }
        var duration = Double(f[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        if s == .spotify { duration /= 1000 }   // Spotify reports milliseconds
        return NowPlayingInfo(source: s, title: f[0], artist: f[1], album: f[2], duration: duration,
                              position: Double(f[4].replacingOccurrences(of: ",", with: ".")) ?? 0,
                              isPlaying: f[5] == "playing", artworkURL: f.count > 6 ? f[6] : nil)
    }

    static func artwork(_ info: NowPlayingInfo) async -> NSImage? {
        if let s = info.artworkURL, let url = URL(string: s), let (data, _) = try? await URLSession.shared.data(from: url) { return NSImage(data: data) }
        if info.source == .music, let d = await AppleScriptRunner.descriptor("tell application \"Music\" to get raw data of artwork 1 of current track") {
            return NSImage(data: d.data)
        }
        return nil
    }

    enum Command: String { case playpause, next = "next track", previous = "previous track" }

    static func send(_ c: Command, to s: NowPlayingInfo.Source) async {
        _ = await AppleScriptRunner.run("tell application \"\(s.rawValue)\" to \(c.rawValue)")
    }

    static func seek(_ seconds: Double, in s: NowPlayingInfo.Source) async {
        _ = await AppleScriptRunner.run("tell application \"\(s.rawValue)\" to set player position to \(seconds)")
    }

    static func recordPlay(_ info: NowPlayingInfo) {
        AppDatabase.shared.write { db in
            let last = try PlayHistory.order(Column("playedAt").desc).fetchOne(db)
            guard last?.title != info.title || last?.artist != info.artist else { return }
            try PlayHistory(title: info.title, artist: info.artist, source: info.source.rawValue, playedAt: Date()).insert(db)
        }
    }

    static func history(limit: Int = 15) -> [PlayHistory] {
        AppDatabase.shared.read { try PlayHistory.order(Column("playedAt").desc).limit(limit).fetchAll($0) } ?? []
    }
}

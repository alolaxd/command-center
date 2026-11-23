import AppKit
import Foundation

@MainActor @Observable
final class NowPlayingViewModel {
    var info: NowPlayingInfo?
    var artwork: NSImage?
    var history: [PlayHistory] = []
    private var artworkKey = ""

    func refresh() async {
        let i = await MusicStore.current()
        info = i
        if let i {
            if i.isPlaying { MusicStore.recordPlay(i) }
            let key = i.title + i.artist
            if key != artworkKey { artworkKey = key; artwork = await MusicStore.artwork(i) }
        } else { artwork = nil; artworkKey = "" }
        history = MusicStore.history()
    }

    func send(_ c: MusicStore.Command) async {
        guard let s = info?.source else { return }
        await MusicStore.send(c, to: s)
        try? await Task.sleep(for: .milliseconds(300))
        await refresh()
    }
}

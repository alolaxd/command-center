import SwiftUI

struct NowPlayingWidget: DashboardWidget {
    static let kind = "music"
    static let title = "Now Playing"
    static let symbol = "music.note"
    static let summary = "Current track from Apple Music or Spotify with artwork, progress, controls and recently played."
    static let category = WidgetCategory.lifestyle
    static let defaultSize = GridSize(4, 2)
    static let refreshInterval: TimeInterval? = 2

    let context: WidgetContext<NowPlayingConfiguration>
    @State private var vm = NowPlayingViewModel()

    init(context: WidgetContext<NowPlayingConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let i = vm.info {
                HStack(spacing: 10) {
                    Group {
                        if let art = vm.artwork { Image(nsImage: art).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").font(.title).foregroundStyle(.secondary) }
                    }
                    .frame(width: 64, height: 64)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(i.title).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(i.artist).font(.caption).lineLimit(1)
                        Text("\(i.album) · \(i.source.rawValue)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(time(i.position)).font(.caption2.monospacedDigit())
                            Slider(value: Binding(get: { i.position }, set: { v in Task { await MusicStore.seek(v, in: i.source) } }), in: 0...max(1, i.duration))
                                .controlSize(.mini).accessibilityLabel("Playback position")
                            Text(time(i.duration)).font(.caption2.monospacedDigit())
                        }
                    }
                }
                HStack(spacing: 18) {
                    Spacer()
                    Button { Task { await vm.send(.previous) } } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                    Button { Task { await vm.send(.playpause) } } label: { Image(systemName: i.isPlaying ? "pause.fill" : "play.fill").font(.title3) }
                        .accessibilityLabel(i.isPlaying ? "Pause" : "Play")
                    Button { Task { await vm.send(.next) } } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                    Spacer()
                }
                .buttonStyle(.borderless)
            } else {
                EmptyStateView(symbol: "music.note", title: "Nothing playing", message: "Start Apple Music or Spotify.")
            }
            if context.config.showHistory && context.size.h >= 3 && !vm.history.isEmpty {
                Divider()
                Text("Recently played").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(vm.history.prefix(context.size.h * 2)) { h in
                    HStack {
                        Text(h.title).font(.caption).lineLimit(1)
                        Text(h.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(h.playedAt.formatted(.relative(presentation: .numeric))).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .refreshing(every: Self.refreshInterval) { await vm.refresh() }
    }

    private func time(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

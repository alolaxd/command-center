import SwiftUI
import Charts

/// Minimal line sparkline. No fills, no glow — just data.
struct Sparkline: View {
    let values: [Double]
    var color: Color = .accentColor
    var lineWidth: CGFloat = 1.5
    var range: ClosedRange<Double>? = nil

    var body: some View {
        GeometryReader { geo in
            let vals = values
            let lo = range?.lowerBound ?? (vals.min() ?? 0)
            let hi = range?.upperBound ?? (vals.max() ?? 1)
            let span = max(hi - lo, 0.0001)
            Path { p in
                guard vals.count > 1 else { return }
                for (i, v) in vals.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(vals.count - 1)
                    let y = geo.size.height * (1 - CGFloat((v - lo) / span))
                    i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var action: (label: String, run: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.callout.weight(.medium))
            if let message { Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if let action { Button(action.label, action: action.run).controlSize(.small) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var detail: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct MeterBar: View {
    let fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

struct ProgressRing: View {
    let fraction: Double
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 6
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

/// Compact search field used by many widgets.
struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.callout)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Inline single-line "add" field.
struct AddField: View {
    var prompt: String
    var onSubmit: (String) -> Void
    @State private var text = ""
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus").foregroundStyle(.secondary).font(.caption)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain).font(.callout)
                .onSubmit {
                    let t = text.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    onSubmit(t); text = ""
                }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct PermissionPrompt: View {
    let symbol: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void
    var body: some View {
        EmptyStateView(symbol: symbol, title: title, message: message, action: (buttonTitle, action))
    }
}

extension Double {
    /// Currency from Settings → General (defaults to the system locale's currency).
    var currency: String { formatted(.currency(code: CurrencySetting.code)) }
    var usd: String { formatted(.currency(code: "USD").precision(.fractionLength(2))) }
    var percent: String { formatted(.percent.precision(.fractionLength(0))) }
}

extension Int64 {
    var bytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

extension UInt64 {
    var bytes: String { ByteCountFormatter.string(fromByteCount: Int64(clamping: self), countStyle: .file) }
}

extension TimeInterval {
    /// 1h 23m / 4m 05s
    var compactDuration: String {
        let s = Int(self)
        if s >= 86400 { return "\(s / 86400)d \((s % 86400) / 3600)h" }
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60 { return String(format: "%dm %02ds", s / 60, s % 60) }
        return "\(s)s"
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// Fixed palette used for user-chosen colors (habits, shortcuts, tags).
enum Palette {
    static let names = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "gray"]
    static func color(_ name: String) -> Color {
        switch name {
        case "purple": .purple
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "teal": .teal
        case "gray": .gray
        default: .blue
        }
    }
}

struct PalettePicker: View {
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Palette.names, id: \.self) { name in
                Circle().fill(Palette.color(name)).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.primary, lineWidth: selection == name ? 2 : 0))
                    .onTapGesture { selection = name }
                    .accessibilityLabel(name).accessibilityAddTraits(selection == name ? .isSelected : [])
            }
        }
    }
}

enum CurrencySetting {
    static var code: String {
        let c = UserDefaults.standard.string(forKey: SettingsKey.currency) ?? ""
        return c.isEmpty ? (Locale.current.currency?.identifier ?? "USD") : c
    }
    static let common = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "CNY", "INR", "AED", "SGD", "BRL", "MXN", "SEK", "KRW"]
}

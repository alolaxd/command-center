import SwiftUI

/// Small block-level Markdown renderer (headings, lists, quotes, code fences, rules, tasks)
/// using AttributedString for inline styles. [[Wiki links]] become tappable.
struct MarkdownView: View {
    let text: String
    var onWikiLink: ((String) -> Void)? = nil

    enum Block: Hashable {
        case heading(Int, String), paragraph(String), bullet(String, Int), ordered(String, String), task(Bool, String)
        case quote(String), code(String), rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "wiki" {
                let raw = url.absoluteString.dropFirst("wiki://".count)
                onWikiLink?(String(raw).removingPercentEncoding ?? String(raw)); return .handled
            }
            return .systemAction
        })
    }

    @ViewBuilder private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let s):
            Text(inline(s)).font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let s): Text(inline(s))
        case .bullet(let s, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); Text(inline(s)) }.padding(.leading, CGFloat(indent) * 12)
        case .ordered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text(n + ".").monospacedDigit(); Text(inline(s)) }
        case .task(let done, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: done ? "checkmark.square" : "square")
                Text(inline(s)).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
            }
        case .quote(let s):
            HStack(spacing: 8) { Rectangle().fill(.tertiary).frame(width: 3); Text(inline(s)).foregroundStyle(.secondary) }
        case .code(let s):
            Text(s).font(.system(.callout, design: .monospaced))
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        case .rule: Divider()
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: Self.linkifyWiki(s), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    /// Rewrites [[Title]] as [Title](wiki://percent-encoded-title).
    static func linkifyWiki(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return s }
        var out = s
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let whole = Range(m.range, in: s), let inner = Range(m.range(at: 1), in: s) else { continue }
            let title = String(s[inner])
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? title
            out.replaceSubrange(whole, with: "[\(title)](wiki://\(encoded))")
        }
        return out
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var inCode = false
        var code: [String] = []
        var para: [String] = []
        func flush() { if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: " "))); para = [] } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode { blocks.append(.code(code.joined(separator: "\n"))); code = []; inCode = false }
                else { flush(); inCode = true }
                continue
            }
            if inCode { code.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                let level = line.prefix { $0 == "#" }.count
                if level <= 6, line.dropFirst(level).first == " " { flush(); blocks.append(.heading(level, String(line.dropFirst(level + 1)))); continue }
            }
            if line == "---" || line == "***" { flush(); blocks.append(.rule); continue }
            if line.hasPrefix("> ") { flush(); blocks.append(.quote(String(line.dropFirst(2)))); continue }
            if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                flush(); blocks.append(.task(!line.hasPrefix("- [ ]"), String(line.dropFirst(6)))); continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                let indent = raw.prefix { $0 == " " }.count / 2
                blocks.append(.bullet(String(line.dropFirst(2)), indent)); continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
               line[line.index(after: dot)...].hasPrefix(" ") {
                flush(); blocks.append(.ordered(String(line[..<dot]), String(line[line.index(dot, offsetBy: 2)...]))); continue
            }
            para.append(line)
        }
        if inCode { blocks.append(.code(code.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}

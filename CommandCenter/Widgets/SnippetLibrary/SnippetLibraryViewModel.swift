import AppKit
import SwiftUI

@MainActor @Observable
final class SnippetLibraryViewModel {
    var snippets: [Snippet] = []
    var query = ""
    var language = "all"
    var selected: Snippet?
    var explanation: String?

    var visible: [Snippet] {
        let base = query.isEmpty ? snippets : SnippetStore.search(query)
        return language == "all" ? base : base.filter { $0.language == language }
    }

    var languages: [String] { Array(Set(snippets.map(\.language))).sorted() }

    func load() { snippets = SnippetStore.all() }

    func copy(_ s: Snippet) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s.code, forType: .string)
        SnippetStore.used(s)
        WidgetBus.shared.toast("Copied “\(s.title)”", symbol: "doc.on.doc")
    }

    func importClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { WidgetBus.shared.toast("Clipboard is empty"); return }
        selected = SnippetStore.importText(text)
        load()
    }

    func explain(_ s: Snippet) async {
        explanation = "…"
        do { explanation = try await AIService.shared.ask("Explain this \(s.language) snippet concisely (what it does, inputs/outputs, gotchas):\n\n```\(s.language)\n\(s.code)\n```") }
        catch { explanation = "⚠️ " + error.localizedDescription }
    }
}

/// Lightweight regex-based syntax highlighter.
enum SyntaxHighlighter {
    static let keywords: [String: [String]] = [
        "swift": ["func", "let", "var", "if", "else", "guard", "return", "struct", "class", "enum", "import", "for", "in", "while", "switch", "case", "self", "async", "await", "try", "throws", "private", "static", "protocol", "extension", "some", "nil", "true", "false"],
        "python": ["def", "class", "import", "from", "as", "return", "if", "elif", "else", "for", "in", "while", "with", "try", "except", "lambda", "None", "True", "False", "self", "async", "await", "yield"],
        "javascript": ["function", "const", "let", "var", "return", "if", "else", "for", "while", "class", "import", "export", "from", "async", "await", "new", "this", "null", "undefined", "true", "false", "=>"],
        "shell": ["if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac", "function", "export", "echo", "local", "return"],
        "go": ["func", "package", "import", "return", "if", "else", "for", "range", "var", "const", "type", "struct", "interface", "go", "defer", "nil"],
        "rust": ["fn", "let", "mut", "pub", "impl", "struct", "enum", "match", "if", "else", "for", "in", "return", "use", "mod", "self", "Some", "None", "Ok", "Err"],
        "sql": ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "JOIN", "ON", "GROUP", "BY", "ORDER", "LIMIT", "AND", "OR", "AS"],
    ]

    static func highlight(_ code: String, language: String) -> AttributedString {
        var out = AttributedString(code)
        let ns = code as NSString
        func paint(_ pattern: String, _ color: Color, options: NSRegularExpression.Options = []) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for m in re.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                guard let r = Range(m.range, in: code), let ar = Range(r, in: out) else { continue }
                out[ar].foregroundColor = color
            }
        }
        let lang = language == "typescript" ? "javascript" : language
        if let kws = keywords[lang] {
            let escaped = kws.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            paint("\\b(\(escaped))\\b", .pink, options: lang == "sql" ? [.caseInsensitive] : [])
        }
        paint(#"\b\d+(\.\d+)?\b"#, .orange)
        paint(#""(\\.|[^"\\])*"|'(\\.|[^'\\])*'"#, .green)
        paint(lang == "python" || lang == "shell" || lang == "ruby" || lang == "yaml" ? #"#.*$"# : lang == "sql" ? #"--.*$"# : #"//.*$|/\*[\s\S]*?\*/"#,
              .gray, options: [.anchorsMatchLines])
        return out
    }
}
